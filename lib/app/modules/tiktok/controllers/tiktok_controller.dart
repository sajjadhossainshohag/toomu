import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import '../../../core/utils/error_text.dart';
import '../../../data/models/tiktok_item.dart';
import '../../../data/providers/tiktok/tiktok_feed.dart';
import '../tiktok_prefetch.dart';

/// Plays one TikTok video at a time (the one on screen, on a loop).
abstract class TiktokPlayback {
  Future<void> play(TiktokItem item);
  Future<void> pause();
  Future<void> resume();

  /// Ends TikTok's playback (not a video another screen started since).
  Future<void> stop();

  /// [item] still holds the player (no other screen took it over).
  bool holds(TiktokItem item);
}

/// One feed of the TikTok tab (For You or Following), ad-free, swiped
/// vertically. The video on screen plays only while the tab and this feed
/// are shown and the app is open.
class TiktokController extends GetxController {
  TiktokController({
    required this.source,
    required this.playback,
    required this.tabIndex,
    required this.tab,
    this.prefetch,
    this.selected,
    this.account,
  });

  /// This feed is the one picked at the top (null: the only one).
  final RxBool? selected;

  /// Signed in to TikTok: when it changes, the feed starts over (For You
  /// follows the account; Following is the account's).
  final RxBool? account;

  final TiktokFeedSource source;
  final TiktokPlayback playback;

  /// Downloads the next videos while one plays (swipes start at once).
  final TiktokPrefetcher? prefetch;

  /// Videos after the one on screen whose first seconds load ahead (once
  /// it plays, so they don't slow its start).
  static const preload = 4;

  /// The home screen's tab index, and this tab's.
  final RxInt tabIndex;
  final int tab;

  /// Without a first video by then, the feed shows an error.
  @visibleForTesting
  static Duration startTimeout = const Duration(seconds: 30);

  /// Hidden this long: TikTok's page (a whole browser engine) closes.
  @visibleForTesting
  static Duration idleClose = const Duration(minutes: 2);

  /// A request for more that brought nothing may be repeated after this.
  @visibleForTesting
  static Duration moreRetry = const Duration(seconds: 8);

  /// Asks for more this many videos before the end.
  static const ahead = 4;

  final items = <TiktokItem>[].obs;
  final page = 0.obs;

  /// The video now playing (its id), null while the one on screen opens.
  final playing = RxnString();
  final opening = false.obs;
  final paused = false.obs;

  /// The feed couldn't load (shown instead of the videos).
  final feedError = RxnString();

  /// The video on screen couldn't play.
  final videoError = RxnString();

  final _ids = <String>{};
  StreamSubscription<List<TiktokItem>>? _sub;
  final _workers = <Worker>[];
  AppLifecycleListener? _lifecycle;
  Timer? _startTimer, _idleTimer, _moreTimer;
  bool _tabShown = false, _appShown = true, _askedMore = false;
  bool? _pageActive;
  int _request = 0;

  PageController? _pages;
  PageController get pages =>
      _pages ??= PageController(initialPage: page.value);

  bool get visible => _tabShown && _appShown;
  TiktokItem? get current =>
      page.value < items.length ? items[page.value] : null;

  @override
  void onInit() {
    super.onInit();
    _sub = source.batches.listen(_add);
    _lifecycle = AppLifecycleListener(
      onHide: () => _setApp(false),
      onShow: () => _setApp(true),
    );
    _workers.add(ever(tabIndex, (_) => _update()));
    if (selected != null) _workers.add(ever(selected!, (_) => _update()));
    if (account != null) {
      _workers.add(ever(account!, (_) => unawaited(reset())));
    }
    _update();
  }

  @override
  void onClose() {
    _request++;
    _sub?.cancel();
    for (final w in _workers) {
      w.dispose();
    }
    _lifecycle?.dispose();
    _startTimer?.cancel();
    _idleTimer?.cancel();
    _moreTimer?.cancel();
    _pages?.dispose();
    unawaited(playback.stop());
    unawaited(source.close());
    unawaited(prefetch?.clear());
    super.onClose();
  }

  void _update() => _setTab(tabIndex.value == tab && (selected?.value ?? true));

  /// Starts over with no videos (another account): the page loads afresh.
  Future<void> reset() async {
    _halt();
    _ids.clear();
    items.clear();
    page.value = 0;
    feedError.value = null;
    videoError.value = null;
    _askedMore = false;
    if (_pages?.hasClients ?? false) _pages!.jumpToPage(0);
    await source.close();
    await prefetch?.clear();
    if (_tabShown) await load();
  }

  void _setTab(bool on) {
    if (_tabShown == on) return;
    _tabShown = on;
    _syncPage();
    if (on) {
      _idleTimer?.cancel();
      if (items.isEmpty) {
        unawaited(load());
      } else {
        unawaited(show(page.value));
      }
    } else {
      _halt();
      _idleTimer = Timer(idleClose, () => unawaited(source.close()));
    }
  }

  /// App hidden: the video pauses; shown again: it carries on.
  void _setApp(bool on) {
    if (_appShown == on) return;
    _appShown = on;
    _syncPage();
    final item = current;
    if (!_tabShown || item == null || playing.value != item.id) return;
    if (on) {
      if (!paused.value) unawaited(playback.resume());
    } else {
      unawaited(playback.pause());
    }
  }

  /// TikTok's page runs only while the tab is on screen.
  void _syncPage() {
    if (_pageActive == visible) return;
    _pageActive = visible;
    source.setActive(visible, background: !_appShown);
  }

  /// Leaving the tab: nothing of TikTok keeps playing.
  void _halt() {
    _request++;
    playing.value = null;
    opening.value = false;
    unawaited(playback.stop());
  }

  /// Loads the feed (first open, or Try again).
  Future<void> load() async {
    feedError.value = null;
    _startTimer?.cancel();
    _startTimer = Timer(startTimeout, () {
      if (items.isEmpty) {
        feedError.value =
            "TikTok didn't answer. Check the connection and try again.";
      }
    });
    try {
      await source.start();
    } catch (e) {
      debugPrint('[TikTok] feed failed: $e');
      _startTimer?.cancel();
      if (items.isEmpty) feedError.value = ErrorText.of(e);
    }
  }

  /// Try again after an error.
  Future<void> retry() async {
    await source.close();
    await load();
  }

  void _add(List<TiktokItem> batch) {
    final fresh = batch.where((i) => _ids.add(i.id)).toList();
    _askedMore = false;
    _moreTimer?.cancel();
    if (fresh.isEmpty) {
      if (atEnd && visible) _askAtEnd(); // only repeats: keep asking
      return;
    }
    final first = items.isEmpty;
    final waiting = atEnd;
    items.addAll(fresh);
    feedError.value = null;
    endStuck.value = false;
    _startTimer?.cancel();
    if (first && visible) {
      unawaited(show(0));
    } else if (waiting && visible) {
      unawaited(show(page.value)); // the end page becomes the first new video
    } else if (visible && playing.value == current?.id) {
      _preloadAfter(page.value); // the end of the feed got new videos
    }
  }

  void _preloadAfter(int i) {
    final from = math.min(i + 1, items.length);
    prefetch?.want(items.sublist(from, math.min(from + preload, items.length)));
  }

  /// Swiped to video [i] (or shown again): it plays, the rest stop.
  Future<void> show(int i) async {
    if (i < 0) return;
    if (i >= items.length) {
      if (items.isNotEmpty) _toEnd(i);
      return;
    }
    // A quick swipe past a video: only the last one asked for plays.
    final request = ++_request;
    page.value = i;
    playing.value = null;
    paused.value = false;
    videoError.value = null;
    if (i >= items.length - ahead) _more();
    if (!visible) return;
    final item = items[i];
    opening.value = true;
    try {
      await playback.play(item);
      if (isClosed || request != _request) return;
      playing.value = item.id;
      _preloadAfter(i);
    } catch (e) {
      debugPrint('[TikTok] ${item.id} failed: $e');
      if (!isClosed && request == _request) videoError.value = ErrorText.of(e);
    } finally {
      if (!isClosed && request == _request) opening.value = false;
    }
  }

  void _more() {
    if (_askedMore) return;
    _askedMore = true;
    _moreTimer?.cancel();
    _moreTimer = Timer(moreRetry, () {
      _askedMore = false;
      if (atEnd && visible) _askAtEnd(); // still nothing: ask again
    });
    unawaited(source.more());
  }

  /// On the page after the last video (TikTok's spinner), waiting for more.
  bool get atEnd => items.isNotEmpty && page.value >= items.length;

  /// Asked a few times at the end and nothing new came.
  final endStuck = false.obs;

  /// Tries at the end before saying nothing came.
  static const endTries = 3;
  int _endAsked = 0;

  void _toEnd(int i) {
    _request++;
    page.value = i;
    playing.value = null;
    opening.value = false;
    paused.value = false;
    videoError.value = null;
    unawaited(playback.stop()); // the last video stops, the spinner shows
    endStuck.value = false;
    _endAsked = 0;
    _askAtEnd();
  }

  void _askAtEnd() {
    if (_endAsked >= endTries) {
      endStuck.value = true;
      return;
    }
    _endAsked++;
    _askedMore = false;
    _more();
  }

  /// "Try again" on the end page.
  void retryEnd() {
    endStuck.value = false;
    _endAsked = 0;
    _askAtEnd();
  }

  /// The feed came to rest on video [i]: it plays, unless it already is
  /// (a swipe that fell back to the same video).
  void settled(int i) {
    if (i == page.value && (opening.value || playing.value == current?.id)) {
      return;
    }
    unawaited(show(i));
  }

  /// Tap on the video: pause / play. If another screen took the player
  /// meanwhile, the video opens again.
  Future<void> togglePause() async {
    final item = current;
    if (item == null) return;
    if (playing.value != item.id || !playback.holds(item)) {
      return show(page.value);
    }
    paused.toggle();
    await (paused.value ? playback.pause() : playback.resume());
  }
}
