import 'browsing_data.dart';

/// The new-tab page (a Flutter screen, not a web page).
const newTabUrl = 'toomu://newtab';

bool isNewTab(String url) => url.isEmpty || url == newTabUrl;

/// What the address bar shows while you're not typing in it: just the
/// site, like Chrome ("movielinkbd.at"); the whole address when tapped.
String displayAddress(String url) {
  if (isNewTab(url)) return '';
  final uri = Uri.tryParse(url);
  if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) return url;
  final host = uri.host.toLowerCase();
  return host.startsWith('www.') ? host.substring(4) : host;
}

/// Something that looks like an address rather than words to search for.
bool looksLikeAddress(String text) {
  final t = text.trim();
  if (t.isEmpty || t.contains(' ')) return false;
  if (RegExp(r'^[a-z][a-z0-9+.-]*://', caseSensitive: false).hasMatch(t)) return true;
  if (RegExp(r'^localhost(:\d+)?(/.*)?$', caseSensitive: false).hasMatch(t)) return true;
  // host.tld[:port][/path], or an IP address
  return RegExp(r'^[^\s/?#]+\.[a-z0-9-]{2,}(:\d+)?([/?#].*)?$', caseSensitive: false).hasMatch(t) ||
      RegExp(r'^\d{1,3}(\.\d{1,3}){3}(:\d+)?([/?#].*)?$').hasMatch(t);
}

/// Where typing [input] and pressing Go leads: the address, or a search
/// (on YouTube while a YouTube page is open, else Google).
String addressTarget(String input, {String currentUrl = ''}) {
  final text = input.trim();
  if (looksLikeAddress(text)) {
    return RegExp(r'^[a-z][a-z0-9+.-]*://', caseSensitive: false).hasMatch(text) ? text : 'https://$text';
  }
  if (Uri.tryParse(currentUrl)?.host.contains('youtube.com') ?? false) {
    return 'https://m.youtube.com/results?search_query=${Uri.encodeQueryComponent(text)}';
  }
  return googleSearch(text);
}

String googleSearch(String query) => 'https://www.google.com/search?q=${Uri.encodeQueryComponent(query)}';

/// The search words of a Google results page (the bar shows them, like
/// Chrome), else null.
String? searchQueryOf(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  if ((host == 'www.google.com' || host == 'google.com') && uri.path == '/search') return uri.queryParameters['q'];
  return null;
}

enum SuggestionKind { typed, bookmark, history, search }

class Suggestion {
  const Suggestion(this.kind, this.text, this.url, {this.title = ''});

  final SuggestionKind kind;

  /// What the row shows: the search words, or the page's address.
  final String text;

  /// Where tapping it goes.
  final String url;
  final String title;
}

/// Google's suggestion answer (`client=firefox`): `["query", ["a", "b"]]`.
List<String> parseGoogleSuggest(Object? json) {
  if (json is! List || json.length < 2 || json[1] is! List) return const [];
  return [
    for (final s in json[1] as List)
      if (s is String && s.trim().isNotEmpty) s,
  ];
}

/// The suggestion list under the address bar: what was typed, then up to
/// [pages] bookmarks and history pages, then Google's searches.
List<Suggestion> mergeSuggestions(
  String typed, {
  List<PageVisit> bookmarks = const [],
  List<PageVisit> history = const [],
  List<String> searches = const [],
  String currentUrl = '',
  int pages = 3,
  int maxSearches = 5,
}) {
  final text = typed.trim();
  if (text.isEmpty) return const [];
  final out = <Suggestion>[Suggestion(SuggestionKind.typed, text, addressTarget(text, currentUrl: currentUrl))];
  final seenPages = <String>{};
  for (final (kind, list) in [(SuggestionKind.bookmark, bookmarks), (SuggestionKind.history, history)]) {
    for (final p in list) {
      if (seenPages.length >= pages) break;
      if (!seenPages.add(p.bare)) continue;
      out.add(Suggestion(kind, p.bare, p.url, title: p.title));
    }
  }
  final seenSearch = {text.toLowerCase()};
  var added = 0;
  for (final s in searches) {
    if (added >= maxSearches) break;
    if (!seenSearch.add(s.trim().toLowerCase())) continue;
    out.add(Suggestion(SuggestionKind.search, s, googleSearch(s)));
    added++;
  }
  return out;
}

/// Desktop Chrome's User-Agent for "Desktop site" (what Chrome on Android
/// sends then).
const desktopUserAgent =
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36';

/// The desktop address of a page on a site's mobile host (m.facebook.com →
/// www.facebook.com, en.m.wikipedia.org → en.wikipedia.org), or null when
/// [url] isn't on one. A mobile host keeps serving the mobile site even to a
/// desktop User-Agent, so "Desktop site" alone changed nothing there.
String? desktopAddress(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) return null;
  final labels = uri.host.toLowerCase().split('.');
  for (var i = 0; i < 2 && i < labels.length; i++) {
    if (!const {'m', 'mobile', 'touch'}.contains(labels[i])) continue;
    if (labels.length - i <= 2) return null; // "m.co" is the site itself
    final host = [if (i == 0) 'www', ...labels.take(i), ...labels.skip(i + 1)].join('.');
    return uri.replace(host: host).toString();
  }
  return null;
}

/// Find in page's counter: "2/5", or "0/0" when nothing matches.
String findCount(int active, int total) => total == 0 ? '0/0' : '$active/$total';
