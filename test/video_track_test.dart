import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:toomu/app/data/models/video_item.dart';
import 'package:toomu/app/services/settings_service.dart';
import 'package:toomu/app/services/storage_service.dart';
import 'package:toomu/app/services/video_session_service.dart';

import 'support/temp_storage.dart';

/// Background play turns video decoding off (audio only) and mpv keeps that for every later file.
void main() {
  late Directory dir;
  var n = 0;

  setUpAll(() async => dir = await useTempStorageDir());
  tearDownAll(() => deleteTempStorageDir(dir));

  Future<(VideoSessionService, List<bool>)> session(WidgetTester tester) async {
    await tester.runAsync(() async {
      Get.put(StorageService(await tempBox('track_${n++}', dir)));
      Get.put(StorageService(await tempBox('track_${n++}', dir)), tag: StorageService.positionsBox);
      Get.put(SettingsService().init());
    });
    addTearDown(Get.reset);
    final sent = <bool>[]; // true: video on (auto), false: off
    final s = Get.put(VideoSessionService())
      ..items.add(VideoItem.file('/storage/emulated/0/Movies/Clip.mp4'))
      ..private = true // stop() would need a real player to save the position
      ..debugActive = true
      ..debugVideoTrack = sent.add;
    return (s, sent);
  }

  testWidgets('the next video has a picture after one that ended while playing in the background', (tester) async {
    final (s, sent) = await session(tester);
    s.setVideoEnabled(false); // left the app with background play on: audio only
    await s.stop(); // that video ends (closed from the notification, or it finished)
    s.debugActive = true; // the next video starts
    s.setVideoEnabled(true);
    expect(sent, [false, true], reason: 'video must be turned back on in mpv, or the next video is blank (nullxnull)');
  });

  testWidgets('turning video on twice sends it once', (tester) async {
    final (s, sent) = await session(tester);
    s.setVideoEnabled(true);
    s.setVideoEnabled(false);
    s.setVideoEnabled(false);
    s.setVideoEnabled(true);
    expect(sent, [false, true]);
  });
}
