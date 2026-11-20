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
  final seeks = <int>[];

  @override
  void seekBy(int seconds) => seeks.add(seconds);

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

  testWidgets('the top bar fits a narrow phone: no "right overflowed by 7.6 pixels" with 1080p60 and picture-in-picture',
      (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(337, 760); // the phone in the report, upright
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      Get.put(StorageService(await tempBox('overlays_${n++}', dir)));
      Get.put(SettingsService().init());
      Get.put(VideoSessionService()).items.add(const VideoItem(
            uri: 'https://v/1080.mp4',
            title: 'All of Science Explained in like 10 minutes',
            qualities: [
              StreamQuality(label: '1080p60', quality: 1080, videoUri: 'https://v/1080.mp4', width: 1920, height: 1080),
            ],
          ));
    });
    addTearDown(Get.reset);
    Get.put<VideoPlaybackController>(_FakePlayback())
      ..exiting.value = true
      ..pipSupported.value = true
      ..controlsVisible.value = true;
    await tester.pumpWidget(const MaterialApp(home: VideoPlayerView()));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('1080p'), findsOneWidget, reason: 'the top bar shows 1080p, not 1080p60');
    final rotate = tester.getRect(find.byTooltip('Rotate'));
    expect(rotate.right, lessThanOrEqualTo(337), reason: 'the last button is on screen');
    expect(rotate.top, lessThan(80), reason: 'the buttons stay at the top, not in the middle of the video');
  });

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

  testWidgets('tapping the video shows the controls on the next frame, not 300 ms later', (tester) async {
    final c = await open(tester);
    c.controlsVisible.value = false;
    await tester.pump();
    final g = await tester.startGesture(const Offset(400, 450));
    await g.up();
    await tester.pump();
    expect(c.controlsVisible.value, isTrue);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('a double tap beside the play button skips 10 s and leaves the controls hidden', (tester) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);
    final c = await open(tester);
    c.controlsVisible.value = false;
    await tester.pump();
    // Just right of centre, where the Next button appears once the first tap shows the controls.
    final next = tester.getCenter(find.byIcon(Icons.skip_next_rounded));
    expect(next.dx / 400, greaterThan(0.65), reason: 'the right-hand skip area');
    for (var i = 0; i < 2; i++) {
      final g = await tester.startGesture(next);
      await g.up();
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(c.seeks, [10], reason: 'the second tap skips; it does not press Next');
    expect(c.controlsVisible.value, isFalse, reason: 'the first tap showed the controls; the double tap puts them back');
    await tester.pump(const Duration(seconds: 4));
  });

  test('when the player opens, it turns with the phone instead of locking to the video', () {
    expect(VideoPlaybackController.followPhone, [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  });

  test('the top bar names qualities without the frame rate: 1080p, 720p', () {
    StreamQuality q(String label) => StreamQuality(label: label, quality: 0, videoUri: '', width: 0, height: 0);
    expect(q('1080p60').shortLabel, '1080p');
    expect(q('720p').shortLabel, '720p');
    expect(q('2160p60').shortLabel, '2160p');
    expect(q('4K').shortLabel, '4K');
  });

  test('the quality menu says 1080p, 720p too; two of one size keep their frame rate', () {
    StreamQuality q(String label) => StreamQuality(label: label, quality: 0, videoUri: '', width: 0, height: 0);
    expect(StreamQuality.menuLabels([q('1080p60'), q('720p60'), q('480p')]), ['1080p', '720p', '480p']);
    expect(StreamQuality.menuLabels([q('1080p60'), q('1080p30'), q('720p')]), ['1080p60', '1080p30', '720p']);
  });
}
