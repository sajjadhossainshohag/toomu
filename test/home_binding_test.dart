import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:toomu/app/modules/downloads/bindings/downloads_binding.dart';
import 'package:toomu/app/modules/downloads/controllers/downloads_controller.dart';
import 'package:toomu/app/modules/home/bindings/home_binding.dart';
import 'package:toomu/app/modules/home/controllers/home_controller.dart';
import 'package:toomu/app/modules/music/controllers/music_controller.dart';
import 'package:toomu/app/modules/settings/controllers/settings_controller.dart';
import 'package:toomu/app/modules/videos/controllers/videos_controller.dart';
import 'package:toomu/app/modules/youtube/controllers/youtube_controller.dart';

/// Regression: the browser's downloads button made DownloadsController,
/// closing the browser deleted it, and with a plain lazyPut its factory went
/// too — the next browser open threw `"DownloadsController" not found` and
/// its top bar became a grey error box.
void main() {
  tearDown(Get.reset);

  void deleted<T>() => Get.delete<T>(force: true);

  test('tab controllers can still be found after a closed page deleted them', () {
    HomeBinding().dependencies();

    deleted<HomeController>();
    deleted<YoutubeController>();
    deleted<DownloadsController>();
    deleted<MusicController>();
    deleted<VideosController>();
    deleted<SettingsController>();

    expect(Get.isRegistered<HomeController>(), isTrue);
    expect(Get.isRegistered<YoutubeController>(), isTrue);
    expect(Get.isRegistered<DownloadsController>(), isTrue);
    expect(Get.isRegistered<MusicController>(), isTrue);
    expect(Get.isRegistered<VideosController>(), isTrue);
    expect(Get.isRegistered<SettingsController>(), isTrue);
  });

  test('the downloads page binding too', () {
    DownloadsBinding().dependencies();
    deleted<DownloadsController>();
    expect(Get.isRegistered<DownloadsController>(), isTrue);
  });
}
