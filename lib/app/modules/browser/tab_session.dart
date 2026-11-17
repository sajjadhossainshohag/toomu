/// The browser's tabs as ids: their order, which one is shown, and which
/// keep a live page in memory. Chrome-like rules, no Flutter: the session
/// controller pairs each id with its page.
class TabSession {
  TabSession({this.maxLive = 4});

  /// Pages kept loaded at once; older ones are dropped and reload when
  /// shown again (what Chrome does on phones short of memory).
  final int maxLive;

  final List<String> _ids = [];
  final List<String> _live = []; // least recently shown first
  final Map<String, String> _opener = {};
  String? _active;

  List<String> get ids => List.unmodifiable(_ids);
  int get length => _ids.length;
  String? get activeId => _active;
  int get activeIndex => _active == null ? -1 : _ids.indexOf(_active!);
  bool isLive(String id) => _live.contains(id);

  /// The tab whose link opened [id] (Back from its first page goes there).
  String? openerOf(String id) => _opener[id];

  /// Adds tab [id]: right after [opener] (a link opened in a new tab), else
  /// at the end (the menu's "New tab"). Shown at once unless [background].
  /// Returns the tabs whose pages were dropped to make room.
  List<String> open(String id, {String? opener, bool background = false}) {
    final at = opener == null ? -1 : _ids.indexOf(opener);
    if (at < 0) {
      _ids.add(id);
    } else {
      // After the opener and the tabs it already opened (Chrome keeps a
      // page's links together, in the order they were opened).
      var i = at + 1;
      while (i < _ids.length && _opener[_ids[i]] == opener) {
        i++;
      }
      _ids.insert(i, id);
      _opener[id] = opener!;
    }
    return background ? const [] : activate(id);
  }

  /// Shows tab [id]; its page becomes live. Returns the tabs whose pages
  /// were dropped (never the shown one).
  List<String> activate(String id) {
    if (!_ids.contains(id)) return const [];
    _active = id;
    _live
      ..remove(id)
      ..add(id);
    final dropped = <String>[];
    while (_live.length > maxLive) {
      dropped.add(_live.removeAt(0));
    }
    return dropped;
  }

  /// Closes tab [id]. When it was shown, its opener is shown next if still
  /// open, else the tab to its left, else the one to its right. Returns
  /// the newly shown tab, or null.
  String? close(String id) {
    final at = _ids.indexOf(id);
    if (at < 0) return _active;
    final opener = _opener.remove(id);
    _ids.removeAt(at);
    _live.remove(id);
    _opener.removeWhere((_, o) => o == id);
    if (_active != id) return _active;
    _active = null;
    if (_ids.isEmpty) return null;
    final next = opener != null && _ids.contains(opener) ? opener : _ids[at > 0 ? at - 1 : 0];
    activate(next);
    return next;
  }

  void closeAll() {
    _ids.clear();
    _live.clear();
    _opener.clear();
    _active = null;
  }

  /// Tabs from the last session: none of them live until shown.
  void restore(List<String> ids) {
    closeAll();
    _ids.addAll(ids);
  }
}

/// The newest [max] of the saved [tabs] (new tabs are saved at the end),
/// and where the shown one is among them.
({List<T> tabs, int active}) newestTabs<T>(List<T> tabs, int active, int max) {
  final drop = tabs.length > max ? tabs.length - max : 0;
  final kept = tabs.sublist(drop);
  return (tabs: kept, active: kept.isEmpty ? -1 : (active - drop).clamp(0, kept.length - 1));
}

int _tabsMade = 0;

/// An id no other tab has: the clock alone repeats when tabs are made in a
/// tight loop (restoring 30 of them).
String newTabId([DateTime? now]) => '${(now ?? DateTime.now()).microsecondsSinceEpoch}-${_tabsMade++}';
