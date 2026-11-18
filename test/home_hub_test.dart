import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:toomu/app/data/models/download_task.dart';
import 'package:toomu/app/data/repositories/video_resume_repository.dart';
import 'package:toomu/app/modules/home/controllers/home_controller.dart';
import 'package:toomu/app/modules/home/home_tabs.dart';
import 'package:toomu/app/modules/home/views/home_hub_view.dart';
import 'package:toomu/app/modules/youtube/controllers/youtube_controller.dart';
import 'package:toomu/app/services/download_service.dart';
import 'package:toomu/app/services/remote_config_service.dart';
import 'package:toomu/app/services/settings_service.dart';
import 'package:toomu/app/services/storage_service.dart';
import 'package:toomu/app/services/youtube_account_service.dart';
import 'package:toomu/app/widgets/app_bottom_nav.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'support/temp_storage.dart';

Video _video(String id, String title) => Video(VideoId(id), title, 'Some Channel', ChannelId('UC${'b' * 22}'), null,
    '2 days ago', null, '', const Duration(minutes: 18), ThumbnailSet(id), null, const Engagement(1, null, null), false);

class _Yt extends YoutubeController {
  final opened = <String>[];

  @override
  // ignore: must_call_super
  void onInit() {}

  @override
  Future<void> watchFromCard(Video video) async => opened.add(video.id.value);

  @override
  Future<void> submit(String input) async => opened.add('search $input');
}

class _Home extends HomeController {
  @override
  // ignore: must_call_super
  void onReady() {}
}

void main() {
  late Directory dir;
  var n = 0;

  setUpAll(() async => dir = await useTempStorageDir());
  tearDownAll(() => deleteTempStorageDir(dir));

  Future<_Yt> open(WidgetTester tester) async {
    await tester.runAsync(() async {
      Get.put(StorageService(await tempBox('hub_${n++}', dir)));
      for (final tag in [StorageService.downloadsBox, StorageService.logsBox, StorageService.positionsBox]) {
        Get.put(StorageService(await tempBox('hub_${n++}', dir)), tag: tag);
      }
      Get.put(SettingsService().init());
      Get.put(YoutubeAccountService());
      Get.put(RemoteConfigService());
      Get.put(DownloadService());
    });
    addTearDown(Get.reset);
    Get.put<HomeController>(_Home());
    final yt = Get.put<YoutubeController>(_Yt()) as _Yt;
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const GetMaterialApp(home: Scaffold(body: SafeArea(child: HomeHubView()))));
    return yt;
  }

  test('the tabs are Home, YouTube, Downloads, Videos and Music; Settings left the bar', () {
    expect(HomeTabs.all.map((t) => t.nav.label), ['Home', 'YouTube', 'Downloads', 'Videos', 'Music']);
  });

  testWidgets('Continue watching shows YouTube videos left part way and opens them', (tester) async {
    final yt = await open(tester);
    expect(find.text('Continue watching'), findsNothing);
    expect(find.textContaining('tap Share there'), findsOneWidget, reason: 'an empty Home says how to download');

    yt.watched.assignAll([_video('aaaaaaaaaaa', 'Half watched'), _video('bbbbbbbbbbb', 'Never started')]);
    await tester.runAsync(
        () => VideoResumeRepository.instance.save('yt:aaaaaaaaaaa', const Duration(minutes: 6), const Duration(minutes: 18)));
    await tester.pump();
    expect(find.text('Continue watching'), findsOneWidget);
    expect(find.text('Half watched'), findsOneWidget);
    expect(find.text('Never started'), findsNothing);
    expect(find.textContaining('tap Share there'), findsNothing);

    await tester.tap(find.text('Half watched'));
    expect(yt.opened, ['aaaaaaaaaaa']);
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
  });

  testWidgets('words typed on Home search YouTube in the YouTube tab', (tester) async {
    final yt = await open(tester);
    await tester.enterText(find.byType(TextField), 'lofi beats');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(Get.find<HomeController>().tabIndex.value, HomeTabs.indexOf(HomeTabs.youtube));
    expect(yt.opened, ['search lofi beats']);
  });

  testWidgets('the Downloads tab shows how many are running', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        bottomNavigationBar: AppBottomNav(
          items: const [
            AppNavItem(label: 'Home', icon: Iconsax.home_2_copy, activeIcon: Iconsax.home_2),
            AppNavItem(label: 'Downloads', icon: Iconsax.document_download_copy, activeIcon: Iconsax.document_download),
          ],
          index: 0,
          onTap: (_) {},
          badges: const [0, 2],
        ),
      ),
    ));
    expect(find.text('2'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^Downloads, 2')), findsOneWidget, reason: 'screen readers hear the count');
    semantics.dispose();
  });
}
