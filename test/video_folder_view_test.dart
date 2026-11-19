import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:toomu/app/modules/video_player/controllers/video_playback_controller.dart';
import 'package:toomu/app/modules/videos/controllers/videos_controller.dart';
import 'package:toomu/app/modules/videos/views/video_folder_view.dart';
import 'package:toomu/app/routes/app_pages.dart';
import 'package:toomu/app/services/audio_player_service.dart';
import 'package:toomu/app/services/settings_service.dart';
import 'package:toomu/app/services/storage_service.dart';
import 'package:toomu/app/services/video_session_service.dart';

import 'support/temp_storage.dart';

class _NoScan extends VideosController {
  @override
  Future<void> load() async {}
}

void main() {
  late Directory dir;

  setUpAll(() async => dir = await useTempStorageDir());
  tearDownAll(() => deleteTempStorageDir(dir));

  testWidgets('a video folder rotated while the player is open over it does not crash', (tester) async {
    await tester.runAsync(() async {
      Get.put(StorageService(await tempBox('folder_main', dir)));
      Get.put(StorageService(await tempBox('folder_queue', dir)), tag: StorageService.queueBox);
      Get.put(SettingsService().init());
      Get.put(AudioPlayerService());
      Get.put(VideoSessionService());
    });
    addTearDown(Get.reset);
    Get.put<VideosController>(_NoScan());
    await tester.pumpWidget(GetMaterialApp(
      initialRoute: '/',
      getPages: [
        GetPage(name: '/', page: () => const Scaffold()),
        GetPage(name: Routes.videoFolder, page: () => const VideoFolderView()),
        GetPage(name: '/player', page: () => const Scaffold()),
      ],
    ));
    Get.toNamed<void>(Routes.videoFolder, arguments: const VideoFolder('Camera', []));
    await tester.pumpAndSettle();
    Get.toNamed<void>('/player', arguments: VideoPlaylist(const [], 0));
    await tester.pumpAndSettle();

    tester.view.physicalSize = Size(tester.view.physicalSize.height, tester.view.physicalSize.width);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpAndSettle();
    Get.back<void>();
    await tester.pumpAndSettle();
    expect(find.text('Camera'), findsOneWidget);
  });
}
