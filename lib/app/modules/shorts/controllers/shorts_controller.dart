import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../../core/utils/error_text.dart';
import '../../../data/models/video_item.dart';

typedef ShortsArgs = ({List<Video> videos, int index});

/// Vertical Shorts: swipe up for the next one; the one on screen plays on a loop.
class ShortsController extends GetxController {
  ShortsController(this.args,
      {required this.resolve, required this.play, required this.stop, this.pause = _nothing, this.prefetch});

  final ShortsArgs args;
  final Future<VideoItem> Function(Video short) resolve;
  final Future<void> Function(VideoItem item) play;
  final Future<void> Function() stop;

  /// Silences the short left behind (the player is shared, so it keeps going until the next one opens).
  final Future<void> Function() pause;

  /// Starts looking a short up before it is on screen.
  final void Function(Video short)? prefetch;

  static Future<void> _nothing() async {}

  late final pages = PageController(initialPage: args.index);
  late final page = args.index.obs;

  /// The short now playing (its id), null while the one on screen loads.
  final playing = RxnString();
  final loading = false.obs;
  final error = RxnString();
  int _request = 0;

  /// How long a swiped-to short has to stay on screen before it is looked up.
  @visibleForTesting
  static Duration settle = const Duration(milliseconds: 300);

  List<Video> get videos => args.videos;

  @override
  void onInit() {
    super.onInit();
    unawaited(show(args.index, now: true));
  }

  @override
  void onClose() {
    pages.dispose();
    unawaited(stop());
    super.onClose();
  }

  /// A lookup is running (for the short on screen or one already swiped past).
  int _looking = 0;

  Future<void> show(int i, {bool now = false}) async {
    // A quick swipe past a short: only the last one asked for plays.
    final request = ++_request;
    final left = playing.value != null || !now;
    page.value = i;
    playing.value = null;
    loading.value = true;
    error.value = null;
    // The player is shared: the short left behind would keep playing until this one opens.
    if (left) unawaited(pause());
    try {
      // While another lookup still runs, wait for the swipe to settle: a quick flick would otherwise start
      // a lookup per short passed, all at once, and the one on screen waited behind them.
      if (!now && _looking > 0) {
        await Future<void>.delayed(settle);
        if (isClosed || request != _request) return;
      }
      final VideoItem item;
      _looking++;
      try {
        item = await resolve(videos[i]);
      } finally {
        _looking--;
      }
      if (isClosed || request != _request) return;
      await play(item);
      if (isClosed) return;
      if (request != _request) {
        // Swiped away while it opened: it must not play over the next one.
        if (playing.value == null) unawaited(pause());
        return;
      }
      playing.value = videos[i].id.value;
      // The next swipe starts without a wait: its links are looked up while this one plays.
      if (i + 1 < videos.length) prefetch?.call(videos[i + 1]);
    } catch (e) {
      debugPrint('[Shorts] ${videos[i].id} failed: $e');
      if (!isClosed && request == _request) error.value = ErrorText.of(e);
    } finally {
      if (!isClosed && request == _request) loading.value = false;
    }
  }
}
