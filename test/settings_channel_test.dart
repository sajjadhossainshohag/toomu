import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:toomu/app/modules/settings/controllers/settings_controller.dart';
import 'package:toomu/app/services/settings_service.dart';
import 'package:toomu/app/services/storage_service.dart';
import 'package:toomu/app/services/youtube_account_service.dart';

import 'support/temp_storage.dart';

class _Settings extends SettingsController {
  final browsed = <String>[];

  @override
  Future<void> openInBrowser(String url) async => browsed.add(url);
}

void main() {
  late Directory dir;

  setUpAll(() async => dir = await useTempStorageDir());
  tearDownAll(() => deleteTempStorageDir(dir));
  tearDown(Get.reset);

  test("Settings → About opens Toomu's official YouTube channel", () async {
    Get.put(StorageService(await tempBox('settings_channel', dir)));
    Get.put(SettingsService().init());
    Get.put(YoutubeAccountService());
    final c = _Settings();
    await c.openYoutubeChannel();
    expect(c.browsed, ['https://www.youtube.com/@toomuapp']);
  });
}
