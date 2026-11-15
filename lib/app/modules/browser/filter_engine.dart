import 'dart:convert';

/// What a page request loads, as far as filter `$type` options care.
enum ResourceType { script, image, stylesheet, subdocument, xmlhttprequest, media, font, object, ping, websocket, other }

/// EasyList-style (Adblock Plus syntax) filters: the rules AdBlock / Adblock
/// Plus use.
///
/// - URL filters block requests (`||ads.example.com^`, `/banner/*/ad_`,
///   `$third-party`, `$domain=`, `$script`…); `@@` filters are exceptions.
///   `@@…$document` turns everything off on a page, `$elemhide` /
///   `$generichide` its element hiding.
/// - `##selector` hides elements everywhere, `site.com##selector` on one
///   site; `#@#` are hiding exceptions.
///
/// Not supported (skipped, never half-applied): regex filters, `$popup`
/// (the redirect guard handles popups), `$csp`/`$rewrite`/…, extended
/// selectors (`#?#`, `:-abp-has`, `:has-text`) and snippets (`#$#`).
class FilterEngine {
  FilterEngine._();

  static FilterEngine parse(String text) {
    final e = FilterEngine._();
    for (final raw in const LineSplitter().convert(text)) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('!') || line.startsWith('[')) continue;
      e._add(line);
    }
    e._finish();
    return e;
  }

  // ---------------------------------------------------------- URL filters

  final _block = <String, List<NetworkFilter>>{};
  final _allow = <String, List<NetworkFilter>>{};
  final _documentAllow = <NetworkFilter>[];
  final _elemhideAllow = <NetworkFilter>[];
  final _generichideAllow = <NetworkFilter>[];

  int get networkFilterCount =>
      [..._block.values, ..._allow.values].fold(0, (n, l) => n + l.length);

  /// `true` block, `false` an exception allows it, `null` no filter says.
  bool? decide(String url, {required String pageUrl, required bool thirdParty, ResourceType? type}) {
    final lower = url.toLowerCase();
    final tokens = _tokens(lower);
    final pageHost = hostOf(pageUrl);
    bool hit(Map<String, List<NetworkFilter>> index) {
      for (final t in tokens) {
        final list = index[t];
        if (list == null) continue;
        for (final f in list) {
          if (f.matches(url, lower, pageHost: pageHost, thirdParty: thirdParty, type: type)) return true;
        }
      }
      return false;
    }

    if (hit(_allow)) return false;
    if (hit(_block)) return true;
    return null;
  }

  /// `@@…$document`: no blocking or hiding at all on this page.
  bool pageAllowed(String pageUrl) => _pageRule(_documentAllow, pageUrl);

  // -------------------------------------------------------- element hiding

  final _generic = <String>[];
  final _genericExceptions = <String>{};

  /// Selectors for everywhere except some sites (`~a.com##.ad`).
  final _genericExcept = <(String, List<String>)>[];
  final _specific = <String, List<String>>{};
  final _specificExceptions = <String, Set<String>>{};

  /// The general hiding rules as one stylesheet (the same on every site).
  late final String genericCss = _css(_generic.where((s) => !_genericExceptions.contains(s)));

  int get genericSelectorCount => _generic.length;

  /// For the page at [url]: whether [genericCss] applies, and its own rules.
  ({bool generic, String css}) hidingFor(String url) {
    if (pageAllowed(url) || _pageRule(_elemhideAllow, url)) return (generic: false, css: '');
    final host = hostOf(url);
    final domains = _parentDomains(host);
    final excepted = <String>{..._genericExceptions};
    for (final d in domains) {
      excepted.addAll(_specificExceptions[d] ?? const {});
    }
    final selectors = <String>{
      for (final d in domains) ...?_specific[d],
      for (final (sel, except) in _genericExcept)
        if (!except.any((d) => onDomain(host, d))) sel,
    }..removeAll(excepted);
    return (generic: !_pageRule(_generichideAllow, url), css: _css(selectors));
  }

  // --------------------------------------------------------------- parsing

  static final _cosmetic = RegExp(r'^([^/*|@"!]*?)#([@?$])?#(.+)$');
  static final _options = RegExp(r'\$(~?[\w-]+(?:=[^,]*)?(?:,~?[\w-]+(?:=[^,]*)?)*)$');

  /// Selector syntax only some blockers understand: a stylesheet can't.
  static const _extended = [
    ':-abp-', ':has-text(', ':xpath(', ':matches-css', ':upward(', ':remove(', ':style(',
    ':matches-path(', ':min-text-length(', ':watch-attr(', ':others(', ':contains(', ':matches-attr(',
  ];

  void _add(String line) {
    if (line.contains('#%#') || line.contains('#@%#') || line.contains('##+js') || line.contains('##^')) return;
    final c = _cosmetic.firstMatch(line);
    if (c != null) return _addHiding(c.group(1)!, c.group(2), c.group(3)!);
    _addNetwork(line);
  }

  void _addHiding(String domainList, String? kind, String selector) {
    if (kind == '?' || kind == r'$') return; // extended selectors, snippets
    if (_extended.any(selector.contains)) return;
    final include = <String>[], exclude = <String>[];
    for (final d in domainList.toLowerCase().split(',')) {
      final t = d.trim();
      if (t.isEmpty) continue;
      t.startsWith('~') ? exclude.add(t.substring(1)) : include.add(t);
    }
    final exception = kind == '@';
    if (include.isEmpty) {
      if (exception) {
        _genericExceptions.add(selector);
      } else if (exclude.isEmpty) {
        _generic.add(selector);
      } else {
        _genericExcept.add((selector, exclude));
      }
      return;
    }
    for (final d in include) {
      exception
          ? (_specificExceptions[d] ??= <String>{}).add(selector)
          : (_specific[d] ??= <String>[]).add(selector);
    }
  }

  static const _typeNames = {
    'script': ResourceType.script,
    'image': ResourceType.image,
    'stylesheet': ResourceType.stylesheet,
    'css': ResourceType.stylesheet,
    'subdocument': ResourceType.subdocument,
    'frame': ResourceType.subdocument,
    'xmlhttprequest': ResourceType.xmlhttprequest,
    'xhr': ResourceType.xmlhttprequest,
    'media': ResourceType.media,
    'font': ResourceType.font,
    'object': ResourceType.object,
    'ping': ResourceType.ping,
    'websocket': ResourceType.websocket,
    'other': ResourceType.other,
  };

  void _addNetwork(String line) {
    var p = line;
    final exception = p.startsWith('@@');
    if (exception) p = p.substring(2);
    if (p.startsWith('/') && p.length > 2 && (p.endsWith('/') || RegExp(r'/\$[^/]*$').hasMatch(p))) return; // regex

    bool? thirdParty;
    var matchCase = false, document = false, elemhide = false, generichide = false;
    var include = <String>[], exclude = <String>[];
    final types = <ResourceType>{}, notTypes = <ResourceType>{};

    final o = _options.firstMatch(p);
    if (o != null) {
      p = p.substring(0, o.start);
      for (final opt in o.group(1)!.split(',')) {
        final eq = opt.indexOf('=');
        final name = (eq < 0 ? opt : opt.substring(0, eq)).toLowerCase();
        final value = eq < 0 ? '' : opt.substring(eq + 1).toLowerCase();
        final negated = name.startsWith('~');
        final bare = negated ? name.substring(1) : name;
        switch (bare) {
          case 'third-party' || '3p':
            thirdParty = !negated;
          case 'first-party' || '1p':
            thirdParty = negated;
          case 'domain' || 'from':
            for (final d in value.split('|')) {
              if (d.isEmpty) continue;
              d.startsWith('~') ? exclude.add(d.substring(1)) : include.add(d);
            }
          case 'match-case':
            matchCase = true;
          case 'document' || 'doc':
            document = true;
          case 'elemhide' || 'ehide':
            elemhide = true;
          case 'generichide' || 'ghide':
            generichide = true;
          case 'important' || 'all':
            break;
          default:
            final type = _typeNames[bare];
            if (type == null) return; // popup, csp, rewrite, redirect…: not applied at all
            negated ? notTypes.add(type) : types.add(type);
        }
      }
    }

    // Leading / trailing wildcards add nothing.
    while (p.startsWith('*')) {
      p = p.substring(1);
    }
    while (p.endsWith('*')) {
      p = p.substring(0, p.length - 1);
    }

    NetworkFilter filter() => NetworkFilter(
          pattern: p,
          thirdParty: thirdParty,
          includeDomains: include,
          excludeDomains: exclude,
          types: types.isEmpty && notTypes.isEmpty
              ? null
              : (types.isEmpty ? ResourceType.values.toSet() : types).difference(notTypes),
          matchCase: matchCase,
        );

    if (document || elemhide || generichide) {
      // Page-wide switches only exist as exceptions.
      if (!exception) return;
      if (document) _documentAllow.add(filter());
      if (elemhide) _elemhideAllow.add(filter());
      if (generichide) _generichideAllow.add(filter());
      return;
    }
    // Too broad to be meant ("" or a couple of letters with no site limit).
    if (p.replaceAll(RegExp(r'[|^]'), '').length < 3 && include.isEmpty) return;
    final f = filter();
    final index = exception ? _allow : _block;
    (index[_keyword(f.pattern, index)] ??= <NetworkFilter>[]).add(f);
  }

  void _finish() => genericCss;

  // ------------------------------------------------------------- matching

  static final _keywordCandidates = RegExp(r'[^a-z0-9%*][a-z0-9%]{2,}(?=[^a-z0-9%*])');
  static final _urlTokens = RegExp(r'[a-z0-9%]{2,}');

  /// The word in [pattern] the filter is filed under: a whole word any
  /// matching URL must contain, used least so far. "" for none.
  static String _keyword(String pattern, Map<String, List<NetworkFilter>> index) {
    var best = '';
    var bestCount = 1 << 30;
    for (final m in _keywordCandidates.allMatches(pattern.toLowerCase())) {
      final word = m.group(0)!.substring(1);
      final count = index[word]?.length ?? 0;
      if (count < bestCount || (count == bestCount && word.length > best.length)) {
        best = word;
        bestCount = count;
      }
    }
    return best;
  }

  static List<String> _tokens(String lowerUrl) =>
      [for (final m in _urlTokens.allMatches(lowerUrl)) m.group(0)!, ''];

  bool _pageRule(List<NetworkFilter> rules, String pageUrl) {
    if (rules.isEmpty) return false;
    final host = hostOf(pageUrl);
    final lower = pageUrl.toLowerCase();
    return rules.any((f) => f.matches(pageUrl, lower, pageHost: host, thirdParty: false, type: null));
  }

  static String hostOf(String url) => (Uri.tryParse(url)?.host ?? '').toLowerCase();

  static bool onDomain(String host, String domain) => host == domain || host.endsWith('.$domain');

  /// "a.b.example.com" → [a.b.example.com, b.example.com, example.com, com].
  static List<String> _parentDomains(String host) {
    final out = <String>[];
    var h = host;
    while (h.isNotEmpty) {
      out.add(h);
      final dot = h.indexOf('.');
      if (dot < 0) break;
      h = h.substring(dot + 1);
    }
    return out;
  }

  /// One rule per selector: one invalid selector in a shared list would
  /// make the browser drop the whole list.
  static String _css(Iterable<String> selectors) =>
      selectors.map((s) => '$s{display:none!important}').join('\n');
}

/// One URL filter (`||ads.example.com^$third-party`).
class NetworkFilter {
  NetworkFilter({
    required this.pattern,
    this.thirdParty,
    this.includeDomains = const [],
    this.excludeDomains = const [],
    this.types,
    this.matchCase = false,
  });

  /// Adblock Plus pattern, without `@@` and options.
  final String pattern;
  final bool? thirdParty;
  final List<String> includeDomains, excludeDomains;

  /// null = any kind of request.
  final Set<ResourceType>? types;
  final bool matchCase;

  // Made on first use: most filters never meet a URL that could match.
  RegExp? _regex;
  RegExp get regex => _regex ??= RegExp(toRegex(pattern), caseSensitive: matchCase);

  bool matches(String url, String lowerUrl,
      {required String pageHost, required bool thirdParty, required ResourceType? type}) {
    final tp = this.thirdParty;
    if (tp != null && tp != thirdParty) return false;
    // Unknown request kind: typed filters still apply (as AdBlock's would
    // to that kind); a site that breaks can be allowed from the shield.
    final t = types;
    if (t != null && type != null && !t.contains(type)) return false;
    if (excludeDomains.any((d) => FilterEngine.onDomain(pageHost, d))) return false;
    if (includeDomains.isNotEmpty && !includeDomains.any((d) => FilterEngine.onDomain(pageHost, d))) return false;
    return regex.hasMatch(matchCase ? url : lowerUrl);
  }

  /// Adblock Plus pattern → regular expression: `||` = the domain or a
  /// subdomain, `|` = start / end anchor, `^` = separator, `*` = anything.
  static String toRegex(String pattern) {
    final b = StringBuffer();
    var i = 0;
    var end = pattern.length;
    if (pattern.startsWith('||')) {
      b.write(r'^[a-z][a-z0-9+.-]*://(?:[^/?#]*\.)?');
      i = 2;
    } else if (pattern.startsWith('|')) {
      b.write('^');
      i = 1;
    }
    final anchoredEnd = end > i && pattern.endsWith('|');
    if (anchoredEnd) end--;
    for (; i < end; i++) {
      final c = pattern[i];
      if (c == '*') {
        b.write('.*');
      } else if (c == '^') {
        b.write(r'(?:[^\w\-.%]|$)');
      } else {
        b.write(RegExp.escape(c));
      }
    }
    if (anchoredEnd) b.write(r'$');
    return b.toString();
  }
}
