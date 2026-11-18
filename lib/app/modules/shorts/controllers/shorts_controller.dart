import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../../core/utils/error_text.dart';
import '../../../data/models/video_item.dart';

typedef ShortsArgs = ({List<Video> videos, int index});

/// Vertical Shorts: swipe up for the next one; the one on screen plays on a loop.
class ShortsController extends GetxController {
  ShortsController(this.args, {required this.resolve, required this.play, required this.stop});

  final ShortsArgs args;
  final Future<VideoItem> Function(Video short) resolve;
  final Future<void> Function(VideoItem item) play;
  final Future<void> Function() stop;

  late final pages = PageController(initialPage: args.index);
  late final page = args.index.obs;

  /// The short now playing (its id), null while the one on screen loads.
  final playing = RxnString();
  final loading = false.obs;
  final error = RxnString();
  int _request = 0;

  List<Video> get videos => args.videos;

  @override
  void onInit() {
    super.onInit();
    unawaited(show(args.index));
  }

  @override
  void onClose() {
    pages.dispose();
    unawaited(stop());
    super.onClose();
  }

  Future<void> show(int i) async {
    // A quick swipe past a short: only the last one asked for plays.
    final request = ++_request;
    page.value = i;
    playing.value = null;
    loading.value = true;
    error.value = null;
    try {
      final item = await resolve(videos[i]);
      if (isClosed || request != _request) return;
      await play(item);
      if (isClosed || request != _request) return;
      playing.value = videos[i].id.value;
    } catch (e) {
      debugPrint('[Shorts] ${videos[i].id} failed: $e');
      if (!isClosed && request == _request) error.value = ErrorText.of(e);
    } finally {
      if (!isClosed && request == _request) loading.value = false;
    }
  }
}
