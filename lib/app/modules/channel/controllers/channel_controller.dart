import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../../core/utils/error_text.dart';
import '../../../data/providers/youtube_provider.dart';

/// Opens a channel page: its id, and the name to show until the channel loads.
typedef ChannelArgs = ({String id, String title});

class ChannelController extends GetxController {
  ChannelController(this.args, this._source);

  final ChannelArgs args;
  final ChannelSource _source;

  final channel = Rxn<Channel>();
  final shorts = false.obs;
  final sort = VideoSorting.newest.obs;
  final videos = <Video>[].obs;
  final loading = true.obs;
  final loadingMore = false.obs;
  final error = RxnString();
  Future<VideosPage?> Function()? _next;
  int _request = 0;

  ChannelId get id => ChannelId(args.id);

  @override
  void onInit() {
    super.onInit();
    unawaited(
      _source
          .channel(id)
          .then((c) {
            if (!isClosed) channel.value = c;
          })
          .catchError((Object e) {
            debugPrint('[Channel] ${args.id} failed: $e');
          }),
    );
    unawaited(load());
  }

  Future<void> showShorts(bool value) async {
    if (shorts.value == value) return;
    shorts.value = value;
    await load();
  }

  Future<void> sortBy(VideoSorting value) async {
    if (sort.value == value) return;
    sort.value = value;
    await load();
  }

  Future<void> load() async {
    // A tab or sort picked while the last one loads: only the newest answer counts.
    final request = ++_request;
    loading.value = true;
    error.value = null;
    videos.clear();
    _next = null;
    try {
      final page = await _source.uploads(id, shorts: shorts.value, sort: sort.value);
      if (isClosed || request != _request) return;
      videos.assignAll(page.videos);
      _next = page.next;
    } catch (e) {
      debugPrint('[Channel] uploads of ${args.id} failed: $e');
      if (!isClosed && request == _request) error.value = ErrorText.of(e);
    } finally {
      if (!isClosed && request == _request) loading.value = false;
    }
  }

  Future<void> loadMore() async {
    final next = _next;
    if (next == null || loadingMore.value || loading.value) return;
    final request = _request;
    loadingMore.value = true;
    try {
      final page = await next();
      if (isClosed || request != _request) return;
      if (page != null) videos.addAll(page.videos);
      _next = page?.next;
    } catch (e) {
      debugPrint('[Channel] more uploads of ${args.id} failed: $e');
    } finally {
      if (!isClosed) loadingMore.value = false;
    }
  }
}
