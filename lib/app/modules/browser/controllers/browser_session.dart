import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/utils/device_profile.dart';
import '../../../data/models/download_task.dart';
import '../../../services/browser_store.dart';
import '../../../widgets/app_snackbar.dart';
import '../ad_blocker.dart';
import '../address.dart';
import '../tab_session.dart';
import 'browser_controller.dart';

/// The browser's tabs, Chrome-style: several pages open at once, the last
/// few kept loaded, all of them back next time the browser opens.
class BrowserSession extends GetxController {
  static BrowserSession get to => Get.find();

  /// Tabs come back from the last session up to this many.
  static const maxRestored = 30;

  final tabs = <BrowserController>[].obs;
  final active = Rxn<BrowserController>();

  /// Tabs with a WebView right now.
  final live = <String>{}.obs;
  final showingSwitcher = false.obs;

  late final TabSession _order = TabSession(maxLive: DeviceProfile.lowEnd ? 2 : 4);
  Timer? _saveTimer;

  /// Each tab's watchers (url, title…), disposed with the tab.
  final Map<String, List<Worker>> _workers = {};

  BrowserController get tab => active.value!;

  /// The tab the browser was opened for ("Refresh link" from Downloads):
  /// once its link is found, the browser closes back to Downloads.
  BrowserController? _openedFor;

  @override
  void onInit() {
    super.onInit();
    FilterLists.browserOpened();
    // History is read now, not at app start (the new-tab page shows it).
    unawaited(BrowserStore.to.loadHistory());
    // The newest ones: new tabs are saved at the end of the list.
    final saved = BrowserStore.to.savedTabs;
    final keep = newestTabs(saved.tabs, saved.active, maxRestored);
    final restored = [for (final t in keep.tabs) _register(BrowserController(url: t.url)..title.value = t.title)];
    _order.restore([for (final c in restored) c.id]);
    tabs.assignAll(restored);

    final arg = Get.arguments;
    if (arg is DownloadTask) {
      _openedFor = newTab(refreshFor: arg);
    } else if (arg == newTabUrl && restored.any((c) => c.tabUrl == newTabUrl)) {
      activate(restored.lastWhere((c) => c.tabUrl == newTabUrl));
    } else if (arg is String && arg.isNotEmpty) {
      newTab(url: arg);
    } else if (restored.isNotEmpty) {
      activate(restored[keep.active]);
    } else {
      newTab();
    }
  }

  @override
  void onClose() {
    _saveTimer?.cancel();
    _saveNow();
    for (final c in [...tabs]) {
      _forget(c, now: true);
    }
    forgetAdHidingJs();
    FilterLists.browserClosed();
    super.onClose();
  }

  /// Stops watching [c] and deletes it. After the frame unless [now]: the
  /// top bar still holds its address field's controller and focus until
  /// it rebuilds, and disposing those under it throws.
  void _forget(BrowserController c, {bool now = false}) {
    for (final w in _workers.remove(c.id) ?? const <Worker>[]) {
      w.dispose();
    }
    c.setThumbnail(null);
    void delete() => Get.delete<BrowserController>(tag: c.id, force: true);
    now ? delete() : WidgetsBinding.instance.addPostFrameCallback((_) => delete());
  }

  BrowserController _register(BrowserController c) {
    Get.put(c, tag: c.id);
    c.openTab = (url, {required background}) => newTab(url: url, opener: c, background: background);
    c.onRefreshed = () => identical(c, _openedFor) ? Get.back<void>() : close(c);
    _workers[c.id] = [
      for (final rx in <RxInterface<Object?>>[c.url, c.title, c.showingNewTab]) ever(rx, (_) => _save()),
    ];
    return c;
  }

  /// Opens a tab: right after [opener] for a link from a page, else at the
  /// end. A tab opened in the [background] gets a "Switch" button.
  BrowserController newTab({
    String url = newTabUrl,
    BrowserController? opener,
    bool background = false,
    DownloadTask? refreshFor,
  }) {
    final c = _register(BrowserController(url: url, refreshFor: refreshFor));
    if (background) c.foreground = false;
    _order.open(c.id, opener: opener?.id, background: true);
    _syncOrder();
    if (background) {
      showSnack(
        'Opened in new tab',
        displayAddress(url),
        duration: const Duration(seconds: 3),
        mainButton: TextButton(
          onPressed: () {
            Get.closeCurrentSnackbar();
            activate(c);
          },
          child: const Text('Switch'),
        ),
      );
    } else {
      activate(c);
    }
    _save();
    return c;
  }

  /// Shows tab [c]; the one shown before goes to the background with a
  /// picture of its page for the switcher.
  void activate(BrowserController c) {
    // A "Switch" button on a tab closed meanwhile.
    if (!tabs.contains(c)) return;
    final prev = active.value;
    // A closed tab isn't "the one before": its page is going away.
    if (prev != null && prev != c && tabs.contains(prev)) {
      // Picture first, then pause, but only if it's still in the background:
      // switching back within the (up to 1 s) picture must not pause the
      // tab that is now shown.
      unawaited(
        prev.snapshot().whenComplete(() {
          if (active.value != prev && tabs.contains(prev)) unawaited(prev.setForeground(false));
        }),
      );
    }
    _drop(_order.activate(c.id));
    live.add(c.id);
    active.value = c;
    unawaited(c.setForeground(true));
    showingSwitcher.value = false;
    _save();
  }

  void _drop(List<String> ids) {
    for (final id in ids) {
      live.remove(id);
      tabs.firstWhereOrNull((t) => t.id == id)?.dropPage();
    }
  }

  void dropBackgroundPages() => _drop(_order.dropBackground());

  /// Closes tab [c]. Closing the last one leaves the switcher empty, like
  /// Chrome: "+" opens a tab, back leaves the browser. The switcher stays
  /// open (closing several tabs there is one tap each).
  void close(BrowserController c) {
    final wasShown = identical(active.value, c);
    final switcher = showingSwitcher.value;
    final next = _order.close(c.id);
    tabs.remove(c);
    live.remove(c.id);
    _forget(c);
    if (next == null) {
      active.value = null;
    } else if (wasShown) {
      activate(tabs.firstWhere((t) => t.id == next));
    }
    showingSwitcher.value = switcher || tabs.isEmpty;
    _save();
  }

  void closeAll() {
    for (final c in [...tabs]) {
      _forget(c);
    }
    _order.closeAll();
    tabs.clear();
    live.clear();
    active.value = null;
    showingSwitcher.value = true;
    _save();
  }

  /// Opens at once; the shown page's picture fills in when it's taken.
  void openSwitcher() {
    unawaited(active.value?.snapshot());
    FocusManager.instance.primaryFocus?.unfocus();
    showingSwitcher.value = true;
  }

  /// Back: the switcher closes, the page goes back, a tab opened from a
  /// link closes and returns to its page. True when the browser should
  /// close.
  Future<bool> handleBack() async {
    if (showingSwitcher.value) {
      if (tabs.isEmpty) return true;
      showingSwitcher.value = false;
      return false;
    }
    final c = active.value;
    if (c == null) return true;
    if (!await c.handleBack()) return false;
    final opener = _order.openerOf(c.id);
    if (opener != null) {
      close(c);
      return false;
    }
    return true;
  }

  /// [tabs] in the session's order (a new tab may sit in the middle).
  void _syncOrder() => tabs.assignAll([for (final id in _order.ids) Get.find<BrowserController>(tag: id)]);

  void _save() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), _saveNow);
  }

  /// Refresh-link tabs are a one-off errand: not brought back next time.
  void _saveNow() {
    final kept = [
      for (final c in tabs)
        if (c.refreshFor == null) c,
    ];
    final list = [for (final c in kept) (url: c.tabUrl, title: c.tabTitle)];
    // The shown tab may be the refresh tab (not saved): then the last one.
    final shown = active.value == null ? -1 : kept.indexOf(active.value!);
    BrowserStore.to.saveTabs(list, shown >= 0 ? shown : kept.length - 1);
  }
}
