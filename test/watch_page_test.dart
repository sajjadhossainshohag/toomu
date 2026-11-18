import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:toomu/app/data/models/video_item.dart';
import 'package:toomu/app/data/providers/youtube_provider.dart';
import 'package:toomu/app/modules/home/controllers/home_controller.dart';
import 'package:toomu/app/modules/video_player/controllers/video_playback_controller.dart';
import 'package:toomu/app/modules/video_player/views/video_player_view.dart';
import 'package:toomu/app/modules/video_player/views/watch_details.dart';
import 'package:toomu/app/modules/youtube/controllers/youtube_controller.dart';
import 'package:toomu/app/services/download_service.dart';
import 'package:toomu/app/services/remote_config_service.dart';
import 'package:toomu/app/services/settings_service.dart';
import 'package:toomu/app/services/storage_service.dart';
import 'package:toomu/app/services/video_session_service.dart';
import 'package:toomu/app/services/youtube_account_service.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'support/temp_storage.dart';

Video _video(String id, String title) => Video(VideoId(id), title, 'Cabin Builders', ChannelId('UC${'b' * 22}'), null,
    '2 days ago', null, 'About it', const Duration(minutes: 18), ThumbnailSet(id), null, const Engagement(123456, 4500, null), false);

class _Source implements WatchSource {
  @override
  Future<Video> video(String id) async => _video(id, 'Building a tiny house');
  @override
  Future<Channel> channel(ChannelId id) async => Channel(id, 'Cabin Builders', '', '', 1200000);
  @override
  Future<List<Video>> related(Video v) async => [_video('bbbbbbbbbbb', 'Street food tour')];
  @override
  Future<({List<Comment> comments, int total})?> comments(Video v) async => null;
}

class _Yt extends YoutubeController {
  @override
  WatchSource get watchSource => _Source();
}

class _Home extends HomeController {
  @override
  // ignore: must_call_super
  void onReady() {}
}

class _Playback extends VideoPlaybackController {
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

  Future<List<Object?>> open(WidgetTester tester, Size screen) async {
    await tester.runAsync(() async {
      Get.put(StorageService(await tempBox('watch_${n++}', dir)));
      for (final tag in [StorageService.downloadsBox, StorageService.logsBox, StorageService.positionsBox]) {
        Get.put(StorageService(await tempBox('watch_${n++}', dir)), tag: tag);
      }
      Get.put(SettingsService().init());
      Get.put(YoutubeAccountService());
      Get.put(RemoteConfigService());
      Get.put(DownloadService());
      Get.put(VideoSessionService()).items.add(const VideoItem(uri: 'x', title: 'Building a tiny house', remoteKey: 'yt:aaaaaaaaaaa'));
    });
    addTearDown(Get.reset);
    Get.put<HomeController>(_Home());
    Get.put<YoutubeController>(_Yt());
    // No video surface in a test: the "closing" state draws none.
    Get.put<VideoPlaybackController>(_Playback())
      ..exiting.value = true
      ..duration.value = const Duration(minutes: 18);
    final asked = <List<Object?>>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setPreferredOrientations') asked.add(call.arguments as List<Object?>);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = screen;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: VideoPlayerView()));
    await tester.pump();
    return asked;
  }

  testWidgets('upright: the video on top, its seek bar at the bottom of it, the watch page underneath', (tester) async {
    final asked = await open(tester, const Size(390, 844));
    const box = 390 * 9 / 16;

    expect(find.byType(WatchDetails), findsOneWidget);
    expect(find.text('Building a tiny house'), findsOneWidget);
    expect(find.text('Street food tour'), findsOneWidget, reason: 'Up next');
    final fullScreen = tester.getRect(find.byIcon(Icons.fullscreen_rounded));
    expect(fullScreen.center.dy, greaterThan(box * 0.8), reason: 'along the bottom edge, not across the middle of the video');
    expect(tester.getRect(find.byType(Slider)).height, lessThan(60), reason: 'the slider must not take the whole player');
    expect(tester.getCenter(find.byIcon(Icons.play_arrow_rounded)).dy, closeTo(box / 2, 4));

    await tester.tap(find.byIcon(Icons.fullscreen_rounded));
    expect(asked.last, ['DeviceOrientation.landscapeLeft', 'DeviceOrientation.landscapeRight']);
    await tester.pump(const Duration(seconds: 5)); // let the hide timers run out
  });

  testWidgets('turned sideways: the whole screen is the player', (tester) async {
    await open(tester, const Size(844, 390));
    expect(find.byType(WatchDetails), findsNothing);
    expect(find.byIcon(Icons.lock_open_rounded), findsOneWidget, reason: 'the full controls, with lock and aspect');
    await tester.pump(const Duration(seconds: 5));
  });
}
