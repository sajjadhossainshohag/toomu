/// Browsing history and bookmarks, as plain data with Chrome-like rules.
/// BrowserStore keeps them on disk.
library;

import 'dart:collection';

class PageVisit {
  PageVisit({required this.url, required this.title, required this.at});

  factory PageVisit.fromJson(Map<String, dynamic> j) => PageVisit(
    url: j['u'] as String? ?? '',
    title: j['t'] as String? ?? '',
    at: DateTime.fromMillisecondsSinceEpoch(j['a'] as int? ?? 0),
  );

  final String url;
  final String title;
  final DateTime at;

  Map<String, dynamic> toJson() => {'u': url, 't': title, 'a': at.millisecondsSinceEpoch};

  PageVisit copyWith({String? title, DateTime? at}) =>
      PageVisit(url: url, title: title ?? this.title, at: at ?? this.at);

  // Worked out once per visit: suggestions scan every visit on each key
  // press, the new-tab page on each page visited.

  /// "example.com/page" — the address without scheme and www.
  late final String bare = bareUrl(url);

  /// "youtube.com" for www.youtube.com and m.youtube.com: one site.
  late final String site = siteOf(url);

  /// Title and address in lower case, for searching.
  late final String searchText = '$title $bare'.toLowerCase();
}

final _scheme = RegExp(r'^[a-z]+://', caseSensitive: false);
final _mobileOrWww = RegExp(r'^(www|m)\.');
final _spaces = RegExp(r'\s+');

/// [url] without scheme, "www." and a trailing slash: how it's matched.
String bareUrl(String url) {
  var s = url.replaceFirst(_scheme, '');
  if (s.toLowerCase().startsWith('www.')) s = s.substring(4);
  return s.endsWith('/') ? s.substring(0, s.length - 1) : s;
}

/// The site of [url] without "www." / "m." (empty if it has none).
String siteOf(String url) => Uri.tryParse(url)?.host.replaceFirst(_mobileOrWww, '') ?? '';

/// Only real web pages are remembered (not the new-tab page, data: …).
bool remembered(String url) {
  final u = url.toLowerCase();
  return u.startsWith('http://') || u.startsWith('https://');
}

/// Pages visited, newest first.
class BrowsingHistory {
  BrowsingHistory([Iterable<PageVisit> saved = const [], this.cap = 3000]) {
    _entries.addAll(saved);
  }

  final int cap;
  final List<PageVisit> _entries = [];

  /// A reload or a return within this long updates the visit instead of
  /// adding another row.
  static const sameVisit = Duration(minutes: 30);

  /// A read-only view (no copy).
  List<PageVisit> get entries => UnmodifiableListView(_entries);

  List<PageVisit>? _mostVisited;
  int _mostVisitedN = 0;

  /// Forgets what was worked out from the visits.
  void _changed() => _mostVisited = null;

  /// Records a visit; false when there was nothing to record.
  bool visit(String url, String title, DateTime now) {
    if (!remembered(url)) return false;
    final bare = bareUrl(url);
    final latest = _entries.isEmpty ? null : _entries.first;
    if (latest != null && latest.bare == bare && now.difference(latest.at) < sameVisit) {
      _entries[0] = latest.copyWith(title: title.isEmpty ? latest.title : title, at: now);
    } else {
      _entries.insert(0, PageVisit(url: url, title: title, at: now));
      if (_entries.length > cap) _entries.removeRange(cap, _entries.length);
    }
    _changed();
    return true;
  }

  /// The page's title arrived after its address; false when nothing changed.
  bool retitle(String url, String title) {
    if (title.isEmpty || _entries.isEmpty) return false;
    final first = _entries.first;
    if (first.title == title || first.bare != bareUrl(url)) return false;
    _entries[0] = first.copyWith(title: title);
    _changed();
    return true;
  }

  void remove(PageVisit v) {
    if (_entries.remove(v)) _changed();
  }

  void clear() {
    _entries.clear();
    _changed();
  }

  /// Visits whose title or address contains every word of [query].
  List<PageVisit> search(String query) {
    final words = query.toLowerCase().split(_spaces).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return entries;
    return _entries.where((v) => words.every(v.searchText.contains)).toList();
  }

  /// Visits grouped under "Today", "Yesterday" or the date, newest first.
  List<({String label, List<PageVisit> visits})> byDay(List<PageVisit> visits, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final groups = <({String label, List<PageVisit> visits})>[];
    for (final v in visits) {
      final day = DateTime(v.at.year, v.at.month, v.at.day);
      final ago = today.difference(day).inDays;
      final label = switch (ago) {
        0 => 'Today',
        1 => 'Yesterday',
        _ => '${_months[day.month - 1]} ${day.day}${day.year == now.year ? '' : ', ${day.year}'}',
      };
      if (groups.isEmpty || groups.last.label != label) groups.add((label: label, visits: <PageVisit>[]));
      groups.last.visits.add(v);
    }
    return groups;
  }

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  /// Most visited sites for the new-tab page: one tile per site (its most
  /// visited page), busiest first. Worked out again only after a change.
  List<PageVisit> mostVisited(int n) {
    final cached = _mostVisited;
    if (cached != null && _mostVisitedN == n) return cached;
    _mostVisitedN = n;
    return _mostVisited = _countSites(n);
  }

  List<PageVisit> _countSites(int n) {
    final count = <String, int>{};
    final best = <String, PageVisit>{};
    for (final v in _entries) {
      final host = v.site;
      if (host.isEmpty) continue;
      count[host] = (count[host] ?? 0) + 1;
      best.putIfAbsent(host, () => v); // newest visit of the site
    }
    final hosts = count.keys.toList()..sort((a, b) => count[b]!.compareTo(count[a]!));
    return [for (final h in hosts.take(n)) best[h]!];
  }

  /// Pages for the address-bar suggestions: addresses starting with what
  /// was typed first, then titles or addresses containing it.
  List<PageVisit> suggest(String query, int n) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final seen = <String>{};
    final starts = <PageVisit>[];
    final contains = <PageVisit>[];
    for (final v in _entries) {
      if (!seen.add(v.bare)) continue;
      if (v.searchText.contains(q)) {
        // searchText is "title bare": the address part starts after the title.
        if (v.bare.toLowerCase().startsWith(q)) {
          starts.add(v);
          // Those come first: enough of them, and nothing later can beat them.
          if (starts.length >= n) break;
        } else {
          contains.add(v);
        }
      }
    }
    return [...starts, ...contains].take(n).toList();
  }
}

/// Starred pages, newest first.
class Bookmarks {
  Bookmarks([Iterable<PageVisit> saved = const []]) {
    _items.addAll(saved);
  }

  final List<PageVisit> _items = [];

  List<PageVisit> get items => List.unmodifiable(_items);

  bool has(String url) {
    final b = bareUrl(url);
    return _items.any((i) => i.bare == b);
  }

  /// Stars or unstars [url]; true when it is now bookmarked.
  bool toggle(String url, String title, DateTime now) {
    if (has(url)) {
      remove(url);
      return false;
    }
    if (!remembered(url)) return false;
    _items.insert(0, PageVisit(url: url, title: title, at: now));
    return true;
  }

  void remove(String url) {
    final b = bareUrl(url);
    _items.removeWhere((i) => i.bare == b);
  }

  List<PageVisit> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return items;
    return _items.where((i) => i.searchText.contains(q)).toList();
  }
}
