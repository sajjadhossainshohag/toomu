import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:toomu/app/data/models/download_task.dart';
import 'package:toomu/app/modules/downloads/controllers/downloads_controller.dart';
import 'package:toomu/app/modules/home/controllers/home_controller.dart';
import 'package:toomu/app/services/download_service.dart';
import 'package:toomu/app/services/remote_config_service.dart';
import 'package:toomu/app/services/settings_service.dart';
import 'package:toomu/app/services/storage_service.dart';

import 'support/temp_storage.dart';

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

  Future<(HomeController, DownloadsController)> open(WidgetTester tester) async {
    await tester.runAsync(() async {
      Get.put(StorageService(await tempBox('sel_${n++}', dir)));
      for (final tag in [StorageService.downloadsBox, StorageService.logsBox, StorageService.positionsBox]) {
        Get.put(StorageService(await tempBox('sel_${n++}', dir)), tag: tag);
      }
      Get.put(SettingsService().init());
      Get.put(RemoteConfigService());
      Get.put(DownloadService());
    });
    addTearDown(Get.reset);
    return (Get.put<HomeController>(_Home()), Get.put(DownloadsController()));
  }

  testWidgets('a selection left on a tab that is no longer shown does not swallow back or act off screen',
      (tester) async {
    final (home, downloads) = await open(tester);

    downloads.selection.toggle('a');
    downloads.tab.value = 1;
    expect(downloads.selection.active, isFalse, reason: 'Downloading → Completed');

    downloads.selection.toggle('a');
    home.tabIndex.value = home.tabIndex.value + 1;
    expect(downloads.selection.active, isFalse, reason: 'another home tab');
  });

  testWidgets('a download that finishes while selected is not deleted unseen from the Completed tab', (tester) async {
    final (_, downloads) = await open(tester);
    final task = DownloadTask(
      id: 't1',
      title: 'Clip',
      kind: DownloadKind.video,
      extension: 'mp4',
      filePath: '${dir.path}/Clip.mp4',
      createdAt: DateTime(2026),
      status: DownloadStatus.paused,
    );
    DownloadService.to.tasks.add(task);
    await tester.pumpWidget(const GetMaterialApp(home: Scaffold()));

    downloads.selection.toggle(task.id);
    task.status.value = DownloadStatus.completed;
    unawaited(downloads.deleteSelected());
    await tester.pumpAndSettle();
    expect(find.text('Delete download?'), findsNothing);
    expect(downloads.selection.active, isFalse);
    expect(DownloadService.to.tasks, contains(task));
  });
}
