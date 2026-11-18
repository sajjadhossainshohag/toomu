import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:toomu/app/services/audio_player_service.dart';
import 'package:toomu/app/services/storage_service.dart';

import 'support/temp_storage.dart';

void main() {
  late Directory dir;

  setUpAll(() async => dir = await useTempStorageDir());
  tearDownAll(() => deleteTempStorageDir(dir));

  Future<AudioPlayerService> start(WidgetTester tester, String name) async {
    late AudioPlayerService audio;
    await tester.runAsync(() async {
      Get.put(StorageService(await tempBox('${name}_main', dir)));
      Get.put(StorageService(await tempBox('${name}_queue', dir)), tag: StorageService.queueBox);
      audio = Get.put(AudioPlayerService().init());
    });
    addTearDown(Get.reset);
    await tester.pump();
    return audio;
  }

  testWidgets('starting the app with no music to resume does not create the music player', (tester) async {
    final audio = await start(tester, 'lazy_start');
    expect(audio.hasPlayer, isFalse);
  });

  testWidgets('opening a video does not create the music player just to pause it', (tester) async {
    final audio = await start(tester, 'lazy_video');
    await audio.pause();
    expect(audio.hasPlayer, isFalse);
  });
}
