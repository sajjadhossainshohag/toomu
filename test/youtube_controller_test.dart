import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:toomu/app/modules/youtube/controllers/youtube_controller.dart';
import 'package:toomu/app/services/remote_config_service.dart';
import 'package:toomu/app/services/storage_service.dart';
import 'package:toomu/app/services/youtube_account_service.dart';

import 'support/temp_storage.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await useTempStorageDir();
    Get.put(StorageService(await tempBox('youtube_controller_test', dir)));
    Get.put(YoutubeAccountService());
    Get.put(RemoteConfigService());
  });

  tearDownAll(() async {
    Get.reset();
    await deleteTempStorageDir(dir);
  });

  test('a closed home feed no longer reloads when the YouTube sign-in changes', () async {
    final closed = Get.put(YoutubeController());
    final categories = closed.categories.toList();
    Get.delete<YoutubeController>(force: true);

    YoutubeAccountService.to.signedIn.value = true;
    await Future<void>.delayed(Duration.zero);

    expect(closed.categories, categories);
  });
}
