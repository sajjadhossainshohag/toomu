import 'dart:io';
import 'dart:math';

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
  var videoLoads = 0;
  DateTime? uploaded;

  @override
  Future<Video> video(String id) async {
    videoLoads++;
    final v = _video(id, 'Building a tiny house');
    final at = uploaded;
    if (at == null) return v;
    // A video's own page gives the date and, as "raw", the same date as an ISO string.
    return Video(v.id, v.title, v.author, v.channelId, at, at.toIso8601String(), null, v.description, v.duration,
        v.thumbnails, null, v.engagement, false);
  }
  @override
  Future<Channel> channel(ChannelId id) async => Channel(id, 'Cabin Builders', '', '', 1200000);
  @override
  Future<List<Video>> related(Video v) async => [_video('bbbbbbbbbbb', 'Street food tour')];
  @override
  Future<CommentsPage?> comments(Video v) async =>
      CommentsPage([Comment('@fan', ChannelId('UC${'c' * 22}'), 'Great video', 3, '1 day ago', 2, false, null)], 1);
  @override
  Future<List<Comment>> replies(Comment c) async =>
      [Comment('@author', ChannelId('UC${'b' * 22}'), 'Thanks!', 0, '12 hours ago', 0, false, null)];
}

var _source = _Source();
final _uiModes = <Object?>[];

class _Yt extends YoutubeController {
  @override
  WatchSource get watchSource => _source;
}

class _Home extends HomeController {
  @override
  // ignore: must_call_super
  void onReady() {}
}

class _Playback extends VideoPlaybackController {
  final left = <String>[];

  @override
  void minimize() => left.add('minimize');

  @override
  Future<void> exit() async => left.add('exit');

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

  Future<List<Object?>> open(WidgetTester tester, Size screen, {DateTime? uploaded}) async {
    _source = _Source()..uploaded = uploaded;
    _uiModes.clear();
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
      if (call.method == 'SystemChrome.setEnabledSystemUIMode') _uiModes.add(call.arguments);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = screen;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const GetMaterialApp(home: VideoPlayerView()));
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

  testWidgets('the status bar shows on the watch page and hides only when the player fills the screen', (tester) async {
    await open(tester, const Size(390, 844));
    expect(_uiModes.last, 'SystemUiMode.edgeToEdge');

    tester.view.physicalSize = const Size(844, 390);
    await tester.pump();
    expect(_uiModes.last, 'SystemUiMode.immersiveSticky');

    tester.view.physicalSize = const Size(390, 844);
    await tester.pump();
    expect(_uiModes.last, 'SystemUiMode.edgeToEdge');
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the upload date reads "3 days ago", not as a timestamp', (tester) async {
    await open(tester, const Size(390, 844), uploaded: DateTime.now().subtract(const Duration(days: 3, hours: 1)));
    await tester.pump();
    expect(find.textContaining('3 days ago'), findsOneWidget);
    expect(find.textContaining(RegExp(r'\d{4}-\d\d-\d\d')), findsNothing);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('upright on a phone with a camera cutout: the top bar stays at the top of the video', (tester) async {
    tester.view.padding = const FakeViewPadding(top: 48);
    await open(tester, const Size(360, 800));
    Get.find<VideoPlaybackController>().controlsVisible.value = true;
    await tester.pump();

    // The video starts under the cutout (48); the back button belongs 16 below that.
    expect(tester.getTopLeft(find.byIcon(Icons.keyboard_arrow_down_rounded).first).dy, lessThan(48 + 20),
        reason: 'the cutout moves the video down once, not the top bar again inside it');
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('upright, the player takes the video\'s shape like YouTube: 16:9 at most wide, 4:5 at most tall',
      (tester) async {
    await open(tester, const Size(400, 844));
    final c = Get.find<VideoPlaybackController>();
    expect(c.viewSize, const Size(400, 225), reason: 'shape not known yet: 16:9');

    for (final (aspect, height) in [(4 / 3, 300.0), (9 / 16, 500.0), (1.0, 400.0), (21 / 9, 225.0)]) {
      c.videoAspect.value = aspect;
      await tester.pump();
      expect(c.viewSize.height, closeTo(height, 0.5), reason: 'video $aspect');
    }
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('a new shape slides the player to its height instead of jumping', (tester) async {
    await open(tester, const Size(400, 844));
    final box = find.descendant(of: find.byType(TweenAnimationBuilder<double>), matching: find.byType(SizedBox)).first;
    expect(tester.getSize(box).height, 225);
    Get.find<VideoPlaybackController>().videoAspect.value = 4 / 3;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getSize(box).height, allOf(greaterThan(225), lessThan(300)), reason: 'on its way');
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.getSize(box).height, 300);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the watch page minimizes like YouTube: the top-left chevron and back; full screen back leaves',
      (tester) async {
    await open(tester, const Size(390, 844));
    final c = Get.find<VideoPlaybackController>() as _Playback;
    c.controlsVisible.value = true;
    await tester.pump();
    expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
    await tester.tap(find.byTooltip('Minimize'));
    await tester.binding.handlePopRoute();
    expect(c.left, ['minimize', 'minimize']);

    tester.view.physicalSize = const Size(844, 390);
    await tester.pump();
    await tester.binding.handlePopRoute();
    expect(c.left.last, 'exit');
    await tester.pump(const Duration(seconds: 5));
  });

  test('captions read like YouTube\'s: about 15 px in the small player, about 20 px in full screen', () {
    // media_kit shrinks captions by sqrt(box area / 1920×1080) unless the config gives its own text scaler.
    double drawn(Size box) {
      final config = VideoPlayerView.captions(box, TextScaler.noScaling);
      final size = config.style.fontSize!;
      return config.textScaler?.scale(size) ?? size * sqrt(box.width * box.height / (1920 * 1080));
    }

    expect(drawn(const Size(390, 219)), inInclusiveRange(14, 17));
    expect(drawn(const Size(844, 390)), inInclusiveRange(19, 23));
    expect(drawn(const Size(1600, 900)), lessThanOrEqualTo(30), reason: 'tablets: big, not huge');
    expect(VideoPlayerView.captions(const Size(390, 219), const TextScaler.linear(1.5)).textScaler!.scale(10), 15,
        reason: 'the phone\'s text size setting still counts');
  });

  testWidgets('turned sideways: the whole screen is the player', (tester) async {
    await open(tester, const Size(844, 390));
    expect(find.byType(WatchDetails), findsNothing);
    expect(find.byIcon(Icons.lock_open_rounded), findsOneWidget, reason: 'the full controls, with lock and aspect');
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('turning the phone sideways and back keeps the watch page, without loading it again', (tester) async {
    await open(tester, const Size(390, 844));
    await tester.pump();
    expect(_source.videoLoads, 1);
    tester.view.physicalSize = const Size(844, 390);
    await tester.pump();
    tester.view.physicalSize = const Size(390, 844);
    await tester.pump();
    await tester.pump();
    expect(find.text('Building a tiny house'), findsOneWidget);
    expect(_source.videoLoads, 1, reason: 'full screen and back is the most common gesture here');
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets("a comment's replies show as soon as they arrive", (tester) async {
    await open(tester, const Size(390, 844));
    await tester.pump();
    await tester.tap(find.textContaining('Comments'));
    await tester.pump(); // the sheet starts sliding in
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('2 replies'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Thanks!'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });
}
