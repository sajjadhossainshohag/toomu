import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:toomu/app/data/models/video_item.dart';
import 'package:toomu/app/services/settings_service.dart';
import 'package:toomu/app/services/storage_service.dart';
import 'package:toomu/app/services/video_session_service.dart';

import 'support/temp_storage.dart';

void main() {
  late Directory dir;
  var n = 0;

  setUpAll(() async => dir = await useTempStorageDir());
  tearDownAll(() => deleteTempStorageDir(dir));

  Future<(VideoSessionService, List<String>)> session(WidgetTester tester) async {
    await tester.runAsync(() async {
      Get.put(StorageService(await tempBox('decoder_${n++}', dir)));
      Get.put(StorageService(await tempBox('decoder_${n++}', dir)), tag: StorageService.positionsBox);
      Get.put(SettingsService().init());
    });
    addTearDown(Get.reset);
    final hwdec = <String>[];
    final s = Get.put(VideoSessionService())
      ..items.add(VideoItem.file('/storage/emulated/0/Movies/Long.mp4'))
      ..debugActive = true
      ..debugHwdec = hwdec.add;
    return (s, hwdec);
  }

  // The test framework requires debugPrint restored before the test body ends.
  List<String> logged(void Function() body) {
    final lines = <String>[];
    final print = debugPrint;
    debugPrint = (message, {wrapWidth}) => lines.add(message ?? '');
    try {
      body();
    } finally {
      debugPrint = print;
    }
    return lines;
  }

  void warnings(VideoSessionService s, int count) {
    for (var i = 0; i < count; i++) {
      final pts = 7648.523 + i * 0.16;
      s.mpvLog('[mpv] warn cplayer: Invalid video timestamp: $pts -> $pts');
    }
  }

  testWidgets('a long video that lags with repeated frame timestamps switches to software decoding', (tester) async {
    final (s, hwdec) = await session(tester);
    logged(() => warnings(s, 60));
    expect(hwdec, ['no'], reason: 'the hardware decoder keeps sending broken frames: video lags while audio plays');
  });

  testWidgets('repeated frame timestamp warnings do not push everything else out of the log', (tester) async {
    final (s, _) = await session(tester);
    final lines = logged(() => warnings(s, 300));
    expect(lines.where((l) => l.contains('Invalid video timestamp')).length, lessThanOrEqualTo(3));
  });

  testWidgets('one timestamp warning after a seek keeps hardware decoding', (tester) async {
    final (s, hwdec) = await session(tester);
    logged(() => warnings(s, 1));
    expect(hwdec, isEmpty);
  });
}
