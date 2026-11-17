import 'dart:async';

import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import '../modules/browser/browsing_data.dart';
import 'storage_service.dart';

/// The browser's history, bookmarks and open tabs, kept on disk.
///
/// History has a box of its own, read the first time the browser needs it:
/// GetStorage rewrites a whole box on every write, so saving the open tabs
/// (after every page) mustn't rewrite thousands of visits too, and the app
/// mustn't read them at start-up when the browser isn't opened.
class BrowserStore extends GetxService {
  BrowserStore([StorageService? store, Future<StorageService> Function()? openHistory])
    : _store = store ?? StorageService.browser,
      _openHistory = openHistory ?? _historyBox;

  static BrowserStore get to => Get.find();

  final StorageService _store;
  final Future<StorageService> Function() _openHistory;
  StorageService? _historyStore;
  Future<void>? _historyLoading;

  static const _historyKey = 'history';
  static const _bookmarksKey = 'bookmarks';
  static const _tabsKey = 'tabs';

  static Future<StorageService> _historyBox() async {
    await GetStorage.init(StorageService.historyBox);
    return StorageService(GetStorage(StorageService.historyBox));
  }

  /// Empty until [loadHistory] has read it; visits made meanwhile are kept.
  BrowsingHistory history = BrowsingHistory();
  late final Bookmarks bookmarks = Bookmarks(_visits(_store, _bookmarksKey));

  /// Reads the history once (the browser starts this when it opens).
  Future<void> loadHistory() => _historyLoading ??= _loadHistory();

  Future<void> _loadHistory() async {
    final box = await _openHistory();
    final early = history.entries; // visited while it was loading, newest first
    history = BrowsingHistory([...early, ..._visits(box, _historyKey)]);
    _historyStore = box;
    historyVersion.value++;
    if (early.isNotEmpty) _historyChanged();
  }

  /// Bumped on every change, so screens listing them rebuild.
  final historyVersion = 0.obs;
  final bookmarksVersion = 0.obs;

  Timer? _historySave;

  static List<PageVisit> _visits(StorageService from, String key) => [
    for (final m in from.read<List<dynamic>>(key) ?? const [])
      if (m is Map) PageVisit.fromJson(Map<String, dynamic>.from(m)),
  ];

  void visit(String url, String title) {
    unawaited(loadHistory());
    if (history.visit(url, title, DateTime.now())) _historyChanged();
  }

  void retitle(String url, String title) {
    if (history.retitle(url, title)) _historyChanged();
  }

  void removeVisit(PageVisit v) {
    history.remove(v);
    _historyChanged(now: true);
  }

  /// After loading: clearing before then would bring the saved visits back.
  Future<void> clearHistory() async {
    await loadHistory();
    history.clear();
    _historyChanged(now: true);
  }

  void _historyChanged({bool now = false}) {
    historyVersion.value++;
    _historySave?.cancel();
    // Pages load in bursts (redirects, title): one write for all of them.
    _historySave = Timer(now ? Duration.zero : const Duration(seconds: 2), _saveHistory);
  }

  // Not before it's loaded: that would replace the saved visits (the load
  // saves the early ones with them).
  void _saveHistory() => _historyStore?.write(_historyKey, [for (final v in history.entries) v.toJson()]);

  /// Stars or unstars [url]; true when it is now bookmarked.
  bool toggleBookmark(String url, String title) {
    final on = bookmarks.toggle(url, title, DateTime.now());
    _bookmarksChanged();
    return on;
  }

  void removeBookmark(String url) {
    bookmarks.remove(url);
    _bookmarksChanged();
  }

  void _bookmarksChanged() {
    bookmarksVersion.value++;
    _store.write(_bookmarksKey, [for (final b in bookmarks.items) b.toJson()]);
  }

  /// Open tabs of the last session and which one was shown.
  ({List<({String url, String title})> tabs, int active}) get savedTabs {
    final raw = _store.read<Map<dynamic, dynamic>>(_tabsKey);
    final list = [
      for (final m in (raw?['tabs'] as List?) ?? const [])
        if (m is Map && m['u'] is String) (url: m['u'] as String, title: (m['t'] as String?) ?? ''),
    ];
    return (tabs: list, active: (raw?['active'] as int?) ?? list.length - 1);
  }

  void saveTabs(List<({String url, String title})> tabs, int active) => _store.write(_tabsKey, {
    'tabs': [
      for (final t in tabs) {'u': t.url, 't': t.title},
    ],
    'active': active,
  });

  @override
  void onClose() {
    if (_historySave?.isActive ?? false) {
      _historySave!.cancel();
      _saveHistory();
    }
    super.onClose();
  }
}
