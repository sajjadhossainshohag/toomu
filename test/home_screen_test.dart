import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:toomu/app/data/models/download_task.dart';
import 'package:toomu/app/modules/downloads/controllers/downloads_controller.dart';
import 'package:toomu/app/modules/home/controllers/home_controller.dart';
import 'package:toomu/app/data/providers/youtube_provider.dart';
import 'package:toomu/app/modules/youtube/controllers/youtube_controller.dart';
import 'package:toomu/app/modules/youtube/views/youtube_view.dart';
import 'package:toomu/app/services/download_service.dart';
import 'package:toomu/app/services/remote_config_service.dart';
import 'package:toomu/app/services/settings_service.dart';
import 'package:toomu/app/services/storage_service.dart';
import 'package:toomu/app/services/youtube_account_service.dart';
import 'package:toomu/app/routes/app_pages.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'support/temp_storage.dart';

class _Channels implements ChannelSource {
  @override
  Future<Channel> channel(ChannelId id) async =>
      Channel(id, id.value.endsWith('a') ? 'Alpha Channel' : 'Beta Channel', '', '', 10);

  @override
  Future<VideosPage> uploads(ChannelId id, {required bool shorts, required VideoSorting sort}) async =>
      const VideosPage([]);
}

class _Yt extends YoutubeController {
  final opened = <String>[];

  @override
  ChannelSource get channelSource => _Channels();

  @override
  Future<void> watchFromCard(Video video) async => opened.add(video.id.value);
}

class _Home extends HomeController {
  @override
  // ignore: must_call_super
  void onReady() {}
}

Video _video(String id, String title) => Video(VideoId(id), title, 'Some Channel', ChannelId('UC${'b' * 22}'), null,
    '2 days ago', null, '', const Duration(minutes: 18), ThumbnailSet(id), null, const Engagement(123456, null, null), false);

void main() {
  late Directory dir;
  var n = 0;

  setUpAll(() async => dir = await useTempStorageDir());
  tearDownAll(() => deleteTempStorageDir(dir));

  Future<_Yt> open(WidgetTester tester) async {
    await tester.runAsync(() async {
      Get.put(StorageService(await tempBox('home_${n++}', dir)));
      for (final tag in [StorageService.downloadsBox, StorageService.logsBox, StorageService.positionsBox]) {
        Get.put(StorageService(await tempBox('home_${n++}', dir)), tag: tag);
      }
      Get.put(SettingsService().init());
      Get.put(YoutubeAccountService());
      Get.put(RemoteConfigService());
      Get.put(DownloadService());
    });
    Get.put<HomeController>(_Home());
    Get.put(DownloadsController());
    final yt = Get.put<YoutubeController>(_Yt()) as _Yt;
    addTearDown(Get.reset);
    yt.history.assignAll(['lofi beats', 'news today']);
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      GetMaterialApp(getPages: AppPages.routes, home: const Scaffold(body: SafeArea(child: YoutubeView()))),
    );
    // After the controller's own first load has started (it never finishes offline).
    yt.feedLoading.value = false;
    yt.feed.assignAll([_video('aaaaaaaaaaa', 'Building a tiny house in 30 days')]);
    await tester.pump();
    return yt;
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5)); // let the controller's timers run out
  }

  testWidgets('the first video is on the first screen: no quick tiles, no recent rows, no second Browser',
      (tester) async {
    await open(tester);
    expect(find.text('Paste link'), findsNothing, reason: 'paste is a button in the search box now');
    expect(find.byTooltip('Paste link'), findsOneWidget);
    for (final gone in ['Recent downloads', 'Recent searches', 'Sites', 'Browser', 'Play offline']) {
      expect(find.text(gone), findsNothing, reason: '"$gone" left Home');
    }
    expect(find.text('YouTube'), findsOneWidget, reason: 'site shortcuts stay, as round icons');
    expect(tester.getRect(find.text('Building a tiny house in 30 days')).bottom, lessThan(844));
    await settle(tester);
  });

  testWidgets('recent searches show while the search box is focused and empty; tapping one searches it',
      (tester) async {
    final yt = await open(tester);
    expect(find.text('lofi beats'), findsNothing);

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(find.text('lofi beats'), findsOneWidget);

    await tester.tap(find.text('lofi beats'));
    await tester.pump();
    expect(yt.searchText.text, 'lofi beats', reason: 'the tap reached the list before the field lost focus');
    expect(find.text('Recent searches'), findsNothing);
    await settle(tester);
  });

  testWidgets('tapping a video card watches it; ⋮ has Download, Share and Copy link', (tester) async {
    final yt = await open(tester);
    expect(find.byTooltip('Download'), findsNothing, reason: 'the card has one ⋮ instead of its own buttons');

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    for (final action in ['Download', 'Share', 'Copy link']) {
      expect(find.text(action), findsOneWidget);
    }
    await tester.tapAt(const Offset(10, 10)); // closes the menu
    await tester.pumpAndSettle();

    await tester.tap(find.text('Building a tiny house in 30 days'));
    await tester.pump();
    expect(yt.opened, ['aaaaaaaaaaa'], reason: 'the card opens the video, not the download sheet');
    await settle(tester);
  });

  testWidgets('the downloads bar shows only while something downloads', (tester) async {
    await open(tester);
    expect(find.textContaining('downloading'), findsNothing);

    final task = DownloadTask(id: '1', title: 'Clip', kind: DownloadKind.video, extension: 'mp4', filePath: '/x/1.mp4', createdAt: DateTime(2026))
      ..status.value = DownloadStatus.running
      ..totalBytes.value = 200
      ..receivedBytes.value = 90;
    DownloadService.to.tasks.add(task);
    await tester.pump();
    expect(find.text('1 downloading · 45%'), findsOneWidget);

    task.status.value = DownloadStatus.completed;
    await tester.pump();
    expect(find.textContaining('downloading'), findsNothing);
    await settle(tester);
  });

  testWidgets('a second channel opened over the first shows the second channel', (tester) async {
    await open(tester);
    Get.toNamed<void>(Routes.channel, arguments: (id: 'UC${'a' * 22}', title: 'Alpha Channel'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Alpha Channel'), findsWidgets);

    // As from the watch page: a video opened from channel A, then channel B's row replaces the player.
    Get.toNamed<void>(Routes.library);
    await tester.pump(const Duration(seconds: 1));
    Get.offNamed<void>(Routes.channel, arguments: (id: 'UC${'b' * 22}', title: 'Beta Channel'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Beta Channel'), findsWidgets, reason: 'not the first channel page again');
    await settle(tester);
  });
}
