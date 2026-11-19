import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:toomu/app/data/models/video_item.dart';
import 'package:toomu/app/data/repositories/video_resume_repository.dart';
import 'package:toomu/app/services/settings_service.dart';
import 'package:toomu/app/services/storage_service.dart';
import 'package:toomu/app/services/video_session_service.dart';

import 'support/temp_storage.dart';

void main() {
  late Directory dir;
  var n = 0;

  setUpAll(() async => dir = await useTempStorageDir());
  tearDownAll(() => deleteTempStorageDir(dir));

  Future<VideoSessionService> session(WidgetTester tester, {required bool private}) async {
    await tester.runAsync(() async {
      Get.put(StorageService(await tempBox('play_${n++}', dir)));
      Get.put(StorageService(await tempBox('play_${n++}', dir)), tag: StorageService.positionsBox);
      Get.put(SettingsService().init());
    });
    addTearDown(Get.reset);
    final s = Get.put(VideoSessionService());
    return s
      ..items.add(VideoItem.file('/storage/emulated/0/Movies/Clip.mp4'))
      ..private = private
      ..debugActive = true;
  }

  testWidgets('a private video stops when its player closes instead of going on in the mini bar', (tester) async {
    final s = await session(tester, private: true);
    await s.detach(keepPlaying: true, minimize: true);
    expect((s.inBackground.value, s.minimized.value), (false, false));
  });

  testWidgets('a private video leaves no resume position behind', (tester) async {
    final s = await session(tester, private: true);
    await s.stop();
    expect(VideoResumeRepository.instance.positionOf(s.items.first.resumeKey), isNull);
  });

  testWidgets('a video moved to the private folder or deleted stops playing in the mini bar', (tester) async {
    final s = await session(tester, private: false);
    s.inBackground.value = true;
    await s.stopIfPlaying(['/storage/emulated/0/Movies/Other.mp4']);
    expect(s.inBackground.value, isTrue, reason: 'another file');
    s.debugActive = false;
    await s.stopIfPlaying(['/storage/emulated/0/Movies/Clip.mp4']);
    expect(s.inBackground.value, isTrue, reason: 'nothing playing');
    s.debugActive = true;
    s.private = true; // stop() would need a real player to save the position
    await s.stopIfPlaying(['/storage/emulated/0/Movies/Clip.mp4']);
    expect(s.inBackground.value, isFalse);
  });
}
