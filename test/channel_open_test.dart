import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:toomu/app/modules/video_player/controllers/video_playback_controller.dart';
import 'package:toomu/app/modules/youtube/controllers/youtube_controller.dart';
import 'package:toomu/app/routes/app_pages.dart';
import 'package:toomu/app/services/settings_service.dart';
import 'package:toomu/app/services/storage_service.dart';
import 'package:toomu/app/services/video_session_service.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'support/temp_storage.dart';

class _Playback extends VideoPlaybackController {
  var minimized = 0;

  @override
  void minimize() {
    minimized++;
    Get.back<void>();
  }

  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  // ignore: must_call_super
  void onClose() {}
}

void main() {
  late Directory dir;

  setUpAll(() async => dir = await useTempStorageDir());
  tearDownAll(() => deleteTempStorageDir(dir));

  testWidgets('View channel on the watch page shrinks the video into the corner and opens the channel over the app',
      (tester) async {
    await tester.runAsync(() async {
      Get.put(StorageService(await tempBox('channel_open_main', dir)));
      for (final tag in [StorageService.positionsBox, StorageService.logsBox]) {
        Get.put(StorageService(await tempBox('channel_open_$tag', dir)), tag: tag);
      }
      Get.put(SettingsService().init());
      Get.put(VideoSessionService());
    });
    addTearDown(Get.reset);
    await tester.pumpWidget(GetMaterialApp(
      initialRoute: '/',
      getPages: [
        GetPage(name: '/', page: () => const Text('home')),
        GetPage(name: Routes.videoPlayer, page: () => const Text('player')),
        GetPage(name: Routes.channel, page: () => const Text('channel')),
      ],
    ));
    Get.toNamed<void>(Routes.videoPlayer);
    await tester.pumpAndSettle();
    final player = Get.put<VideoPlaybackController>(_Playback()) as _Playback;

    final video = Video(VideoId('aaaaaaaaaaa'), 'A video', 'Sarkar Films', ChannelId('UC${'b' * 22}'), null, null,
        null, '', null, ThumbnailSet('aaaaaaaaaaa'), null, const Engagement(0, null, null), false);
    unawaited(YoutubeController().openChannel(video, fromPlayer: true));
    await tester.pumpAndSettle();

    expect(player.minimized, 1);
    expect(find.text('channel'), findsOneWidget);
    Get.back<void>();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget, reason: 'back from the channel returns under the corner video');
  });
}
