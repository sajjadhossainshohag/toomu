import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:toomu/app/data/models/video_item.dart';
import 'package:toomu/app/modules/video_player/controllers/video_playback_controller.dart';
import 'package:toomu/app/modules/video_player/views/video_player_view.dart';
import 'package:toomu/app/services/settings_service.dart';
import 'package:toomu/app/services/storage_service.dart';
import 'package:toomu/app/services/video_session_service.dart';

import 'support/temp_storage.dart';

class _FakePlayback extends VideoPlaybackController {
  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  // ignore: must_call_super
  void onClose() {}
}

void main() {
  late Directory dir;
  var n = 0;

  setUpAll(() async => dir = await useTempStorageDir());
  tearDownAll(() => deleteTempStorageDir(dir));

  Future<_FakePlayback> open(WidgetTester tester) async {
    await tester.runAsync(() async {
      Get.put(StorageService(await tempBox('overlays_${n++}', dir)));
      Get.put(SettingsService().init());
      Get.put(VideoSessionService()).items.add(const VideoItem(uri: 'file:///v/a.mp4', title: 'A video'));
    });
    addTearDown(Get.reset);
    // No video surface in a test: the "closing" state draws none.
    final c = Get.put<VideoPlaybackController>(_FakePlayback())..exiting.value = true;
    await tester.pumpWidget(const MaterialApp(home: VideoPlayerView()));
    return c as _FakePlayback;
  }

  int paintOrder(WidgetTester tester, Finder f) => tester.allElements.toList().indexOf(f.evaluate().single);

  testWidgets('a loader shows while buffering, even with the controls up', (tester) async {
    final c = await open(tester);
    c
      ..playing.value = true
      ..buffering.value = true
      ..controlsVisible.value = true;
    await tester.pump();

    final loader = find.byType(CircularProgressIndicator);
    expect(loader, findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsNothing, reason: 'the play/pause button shows the loader instead');

    c.buffering.value = false;
    await tester.pump();
    expect(loader, findsNothing);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
  });

  testWidgets('changing the view: its name shows above the play/pause button, not under it', (tester) async {
    final c = await open(tester);
    c.cycleFit();
    await tester.pump();

    expect(find.text('Crop'), findsOneWidget);
    expect(
      paintOrder(tester, find.text('Crop')),
      greaterThan(paintOrder(tester, find.byIcon(Icons.play_arrow_rounded))),
      reason: 'later in the tree is painted on top',
    );
    await tester.pump(const Duration(seconds: 4)); // let the hide timers run out
  });

  testWidgets('Rotate turns the screen the other way from how the phone is held, and keeps it there', (tester) async {
    final asked = <List<Object?>>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setPreferredOrientations') asked.add(call.arguments as List<Object?>);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(400, 800); // held upright
    addTearDown(tester.view.reset);
    await open(tester);

    await tester.tap(find.byIcon(Icons.screen_rotation_rounded));
    expect(asked.last, ['DeviceOrientation.landscapeLeft', 'DeviceOrientation.landscapeRight']);

    tester.view.physicalSize = const Size(800, 400); // turned
    await tester.pump();
    await tester.tap(find.byIcon(Icons.screen_rotation_rounded));
    expect(asked.last, ['DeviceOrientation.portraitUp']);
    await tester.pump(const Duration(seconds: 4));
  });

  test('when the player opens, it turns with the phone instead of locking to the video', () {
    expect(VideoPlaybackController.followPhone, [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  });
}
