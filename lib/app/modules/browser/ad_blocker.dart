import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../../core/values/app_constants.dart';
import 'filter_engine.dart';
import 'redirect_guard.dart';

/// Browser ad blocking, the way AdBlock does it:
///  1. requests matching EasyList (or a host on the downloaded hosts list)
///     are answered with nothing;
///  2. a stylesheet hides ad boxes: EasyList's general hiding rules plus the
///     ones for the site;
///  3. EasyList's exceptions (`@@`, `#@#`) win, and the user can allow ads
///     on a site that breaks.
class AdBlocker {
  AdBlocker({
    this.isListed = Blocklist.contains,
    Set<String> Function()? allowedSites,
    FilterEngine? Function()? filters,
  }) : _allowed = allowedSites ?? (() => const {}),
       _filters = filters ?? (() => AdFilters.engine);

  final bool Function(String host) isListed;
  final Set<String> Function() _allowed;
  final FilterEngine? Function() _filters;

  /// The site ads are judged by ("news.example.co.uk" → "example.co.uk").
  static String siteOf(String url) => RedirectGuard.siteOf(Uri.tryParse(url)?.host ?? '');

  bool allowedOn(String pageUrl) {
    final site = siteOf(pageUrl);
    return site.isNotEmpty && _allowed().contains(site);
  }

  /// Whether the page at [pageUrl] may not load [request].
  bool blocks(Uri request, {required String pageUrl, ResourceType? type}) {
    if (request.scheme != 'http' && request.scheme != 'https') return false;
    if (allowedOn(pageUrl)) return false;
    final filters = _filters();
    if (filters != null && filters.pageAllowed(pageUrl)) return false;
    final site = RedirectGuard.siteOf(request.host);
    if (site.isEmpty) return false;
    final thirdParty = site != siteOf(pageUrl);
    final verdict = filters?.decide(request.toString(), pageUrl: pageUrl, thirdParty: thirdParty, type: type);
    if (verdict != null) return verdict;
    // Hosts list: whole sites, so never the page's own.
    return thirdParty && isListed(request.host);
  }

  /// Element hiding for the page at [url]: whether the general stylesheet
  /// applies, and the site's own rules.
  ({bool generic, String css}) hidingFor(String url, {required String pageUrl}) {
    if (allowedOn(pageUrl)) return (generic: false, css: '');
    return _filters()?.hidingFor(url) ?? (generic: true, css: '');
  }

  static const _extensions = {
    'js': ResourceType.script,
    'mjs': ResourceType.script,
    'css': ResourceType.stylesheet,
    'png': ResourceType.image,
    'jpg': ResourceType.image,
    'jpeg': ResourceType.image,
    'gif': ResourceType.image,
    'webp': ResourceType.image,
    'avif': ResourceType.image,
    'svg': ResourceType.image,
    'ico': ResourceType.image,
    'bmp': ResourceType.image,
    'woff': ResourceType.font,
    'woff2': ResourceType.font,
    'ttf': ResourceType.font,
    'otf': ResourceType.font,
    'eot': ResourceType.font,
    'mp4': ResourceType.media,
    'webm': ResourceType.media,
    'mp3': ResourceType.media,
    'm4a': ResourceType.media,
    'ogg': ResourceType.media,
    'm3u8': ResourceType.media,
    'mpd': ResourceType.media,
    'html': ResourceType.subdocument,
    'htm': ResourceType.subdocument,
  };

  /// What a request loads, from its file ending or Accept header; null when
  /// it can't be told (then `$script`-style filters apply to it anyway).
  static ResourceType? typeOf(Uri url, Map<String, String>? headers) {
    final path = url.path.toLowerCase();
    final dot = path.lastIndexOf('.');
    if (dot > path.lastIndexOf('/')) {
      final type = _extensions[path.substring(dot + 1)];
      if (type != null) return type;
    }
    String? accept;
    headers?.forEach((k, v) {
      if (k.toLowerCase() == 'accept') accept = v.toLowerCase();
    });
    final a = accept;
    if (a == null) return null;
    if (a.startsWith('text/css')) return ResourceType.stylesheet;
    if (a.startsWith('image/')) return ResourceType.image;
    if (a.startsWith('text/html')) return ResourceType.subdocument;
    return null;
  }
}

/// EasyList, downloaded weekly and read into a [FilterEngine].
class AdFilters {
  AdFilters._();

  static String url = AppConstants.easylistUrl;
  static FilterEngine? engine;
  static Future<void>? _loading;

  static int _generation = 0;

  static Future<void> load() => _loading ??= _load();

  static void forget() {
    _generation++;
    engine = null;
    _loading = null;
  }

  static Future<void> _load() async {
    final generation = _generation;
    try {
      final file = await cachedList(url, 'easylist.txt');
      if (file == null) return;
      final sw = Stopwatch()..start();
      final parsed = await _parse(file.path);
      if (generation != _generation) return;
      engine = parsed;
      debugPrint(
        '[AdFilters] ${engine!.networkFilterCount} URL filters, '
        '${engine!.genericSelectorCount} hiding rules in ${sw.elapsedMilliseconds} ms',
      );
    } catch (e) {
      debugPrint('[AdFilters] $e');
    }
  }

  // Static: the closure sent to the isolate must not capture anything
  // unsendable.
  static Future<FilterEngine> _parse(String path) =>
      Isolate.run(() => FilterEngine.parse(File(path).readAsStringSync()));
}

/// Common ad boxes (Google AdSense / Ad Manager, AMP ads, ad iframes),
/// hidden even before EasyList is downloaded.
const adSelectors = <String>[
  'ins.adsbygoogle',
  '[id^="google_ads_iframe"]',
  '[id^="div-gpt-ad"]',
  'amp-ad',
  'amp-sticky-ad',
  'iframe[src*="doubleclick.net"]',
  'iframe[src*="googlesyndication.com"]',
  'iframe[src*="adservice.google."]',
];

/// [adHidingJs], built once while the allowed sites and the filter list
/// stay the same: [genericCss] is ~0.5 MB, and every tab's page asks for
/// the script. Tabs then share one string instead of a copy each.
String adHidingJsFor(Set<String> allowedSites, {String genericCss = ''}) {
  final key = (([...allowedSites]..sort()).join(','), identityHashCode(genericCss), genericCss.length);
  final hit = _adScript;
  if (hit != null && hit.key == key) return hit.js;
  final js = adHidingJs(allowedSites, genericCss: genericCss);
  _adScript = (key: key, js: js);
  return js;
}

({(String, int, int) key, String js})? _adScript;

/// The browser closed: no page needs the script until it opens again.
void forgetAdHidingJs() => _adScript = null;

/// Page script (document start, main frame): adds [genericCss] at once,
/// then asks the app (`toomuCss` handler) for the site's own rules and
/// whether the general ones apply there. Does nothing on [allowedSites].
String adHidingJs(Set<String> allowedSites, {String genericCss = ''}) {
  final base = adSelectors.map((s) => '$s{display:none!important}').join('\n');
  return '''
(function () {
  if (window.__toomuAds) return;
  window.__toomuAds = true;
  var host = location.hostname.toLowerCase();
  var allowed = ${jsonEncode(allowedSites.toList()..sort())};
  for (var i = 0; i < allowed.length; i++) {
    var s = allowed[i];
    if (host === s || host.endsWith('.' + s)) return;
  }
  function add(css) {
    var style = document.createElement('style');
    style.textContent = css;
    (document.head || document.documentElement).appendChild(style);
    return style;
  }
  var generic = add(${jsonEncode('$base\n$genericCss')});
  function ask() {
    window.flutter_inappwebview.callHandler('toomuCss', location.href).then(function (r) {
      if (!r) return;
      if (r.generic === false) generic.remove();
      if (r.css) add(r.css);
    });
  }
  if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) ask();
  else window.addEventListener('flutterInAppWebViewPlatformReady', ask, { once: true });
})();
''';
}
