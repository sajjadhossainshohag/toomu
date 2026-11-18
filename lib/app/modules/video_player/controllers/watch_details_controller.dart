import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../../core/utils/error_text.dart';
import '../../../data/providers/youtube_provider.dart';

/// What the watch page shows under the player: details, channel, comments and Up next. Each part loads on its
/// own; one failing leaves the others.
class WatchDetailsController extends GetxController {
  WatchDetailsController(this.videoId, this._source);

  final String videoId;
  final WatchSource _source;

  final video = Rxn<Video>();
  final channel = Rxn<Channel>();
  final related = <Video>[].obs;
  final comments = <Comment>[].obs;
  final commentCount = 0.obs;
  final commentsOff = false.obs;
  final loading = true.obs;
  final error = RxnString();
  final descriptionOpen = false.obs;

  @override
  void onInit() {
    super.onInit();
    unawaited(load());
  }

  Future<void> load() async {
    loading.value = true;
    error.value = null;
    final Video v;
    try {
      v = await _source.video(videoId);
    } catch (e) {
      debugPrint('[Watch] details of $videoId failed: $e');
      if (!isClosed) {
        error.value = ErrorText.of(e);
        loading.value = false;
      }
      return;
    }
    if (isClosed) return;
    video.value = v;
    loading.value = false;
    await Future.wait([
      _part('channel', () async => channel.value = await _source.channel(v.channelId)),
      _part('related', () async => related.assignAll(await _source.related(v))),
      _part('comments', () async {
        final c = await _source.comments(v);
        if (c == null) {
          commentsOff.value = true;
        } else {
          comments.assignAll(c.comments);
          commentCount.value = c.total;
        }
      }),
    ]);
  }

  Future<void> _part(String name, Future<void> Function() load) async {
    try {
      if (!isClosed) await load();
    } catch (e) {
      debugPrint('[Watch] $name of $videoId failed: $e');
    }
  }
}
