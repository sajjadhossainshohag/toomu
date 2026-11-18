import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:toomu/app/data/models/video_item.dart';
import 'package:toomu/app/data/models/yt_info.dart';
import 'package:toomu/app/modules/home/controllers/home_controller.dart';
import 'package:toomu/app/modules/video_player/controllers/video_playback_controller.dart';
import 'package:toomu/app/modules/youtube/controllers/youtube_controller.dart';
import 'package:toomu/app/routes/app_pages.dart';
import 'package:toomu/app/services/download_service.dart';
import 'package:toomu/app/services/remote_config_service.dart';
import 'package:toomu/app/services/settings_service.dart';
import 'package:toomu/app/services/storage_service.dart';
import 'package:toomu/app/services/youtube_account_service.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'support/temp_storage.dart';

class _Yt extends YoutubeController {
  final lookup = Completer<VideoItem>();

  @override
  Future<VideoItem> resolveStream(String id, String title, {YtInfo? info, Duration? duration}) => lookup.future;
}

class _Home extends HomeController {
  @override
  // ignore: must_call_super
  void onReady() {}
}

void main() {
  late Directory dir;
  var n = 0;

  setUpAll(() async => dir = await useTempStorageDir());
  tearDownAll(() => deleteTempStorageDir(dir));

  testWidgets('tapping a video opens the player at once; the stream is looked up in the player, not on the row',
      (tester) async {
    await tester.runAsync(() async {
      Get.put(StorageService(await tempBox('open_${n++}', dir)));
      for (final tag in [StorageService.downloadsBox, StorageService.logsBox, StorageService.positionsBox]) {
        Get.put(StorageService(await tempBox('open_${n++}', dir)), tag: tag);
      }
      Get.put(SettingsService().init());
      Get.put(YoutubeAccountService());
      Get.put(RemoteConfigService());
      Get.put(DownloadService());
    });
    addTearDown(Get.reset);
    Get.put<HomeController>(_Home());
    final yt = Get.put<YoutubeController>(_Yt()) as _Yt;
    VideoPlaylist? opened;
    await tester.pumpWidget(GetMaterialApp(
      home: const Scaffold(),
      getPages: [
        GetPage(name: Routes.videoPlayer, page: () => Builder(builder: (_) {
          opened = Get.arguments as VideoPlaylist;
          return const Scaffold();
        })),
      ],
    ));

    final video = Video(VideoId('aaaaaaaaaaa'), 'Building a tiny house', 'Cabin Builders', ChannelId('UC${'b' * 22}'),
        null, '2 days ago', null, '', const Duration(minutes: 18), ThumbnailSet('aaaaaaaaaaa'), null,
        const Engagement(1, null, null), false);
    unawaited(yt.watchFromCard(video));
    await tester.pumpAndSettle();

    expect(yt.lookup.isCompleted, isFalse);
    final playlist = opened!;
    expect(playlist.items.single.youtubeId, 'aaaaaaaaaaa', reason: 'the watch page can load at once');
    expect(playlist.items.single.title, 'Building a tiny house');
    expect(playlist.resolve, isNotNull);

    const stream = VideoItem(uri: 'https://stream', title: 'Building a tiny house', remoteKey: 'yt:aaaaaaaaaaa');
    yt.lookup.complete(stream);
    expect(await playlist.resolve!(), same(stream));
  });
}
