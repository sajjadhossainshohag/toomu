import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:toomu/app/core/utils/device_profile.dart';
import 'package:toomu/app/modules/browser/controllers/browser_session.dart';
import 'package:toomu/app/modules/browser/views/browser_view.dart';
import 'package:toomu/app/modules/browser/views/new_tab_page.dart';
import 'package:toomu/app/modules/downloads/controllers/downloads_controller.dart';
import 'package:toomu/app/services/download_service.dart';
import 'package:toomu/app/services/remote_config_service.dart';
import 'package:toomu/app/services/browser_store.dart';
import 'package:toomu/app/services/settings_service.dart';
import 'package:toomu/app/services/storage_service.dart';

import 'support/temp_storage.dart';

void main() {
  late Directory dir;
  var n = 0;

  setUpAll(() async => dir = await useTempStorageDir());
  tearDownAll(() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await deleteTempStorageDir(dir);
  });

  Future<void> open(WidgetTester tester) async {
    await tester.runAsync(() async {
      final main = StorageService(await tempBox('view_main_${n++}', dir));
      Get.put(main);
      for (final tag in [StorageService.downloadsBox, StorageService.logsBox, StorageService.positionsBox]) {
        Get.put(StorageService(await tempBox('view_${n++}', dir)), tag: tag);
      }
      Get.put(SettingsService().init());
      Get.put(RemoteConfigService());
      Get.put(DownloadService());
      final history = StorageService(await tempBox('view_history_${n++}', dir));
      Get.put(BrowserStore(main, () async => history));
    });
    addTearDown(() {
      Get.delete<BrowserSession>(force: true);
      Get.reset();
    });
    Get.put(DownloadsController());
    Get.put(BrowserSession());
    await tester.pumpWidget(const GetMaterialApp(home: BrowserView()));
    await tester.pump();
  }

  testWidgets('on a low-end phone the browser opens instead of the "improper use of GetX" error page', (tester) async {
    // 2 GB phones (and the 2 GB emulator): opening TikTok from Home showed the error page, not the site.
    DeviceProfile.lowEnd = true;
    addTearDown(() => DeviceProfile.lowEnd = false);
    await open(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(NewTabPage), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('on other phones the browser opens too', (tester) async {
    await open(tester);
    expect(tester.takeException(), isNull);
    expect(find.byType(NewTabPage), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });
}
