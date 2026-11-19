import 'package:get/get.dart';

import '../../downloads/controllers/downloads_controller.dart';
import '../../music/controllers/music_controller.dart';
import '../../settings/controllers/settings_controller.dart';
import '../../videos/controllers/videos_controller.dart';
import '../../youtube/controllers/youtube_controller.dart';
import '../controllers/home_controller.dart';

class HomeBinding extends Bindings {
  @override
  void dependencies() {
    // fenix: the tabs' controllers can be made again after GetX deletes
    // them. A pushed page that first used one (the browser's downloads
    // button) owned it, and closing that page deleted it for good: the
    // next Get.find threw and the browser's top bar turned into a grey box.
    Get.lazyPut<HomeController>(HomeController.new, fenix: true);
    Get.lazyPut<YoutubeController>(YoutubeController.new, fenix: true);
    Get.lazyPut<DownloadsController>(DownloadsController.new, fenix: true);
    Get.lazyPut<MusicController>(MusicController.new, fenix: true);
    Get.lazyPut<VideosController>(VideosController.new, fenix: true);
    Get.lazyPut<SettingsController>(SettingsController.new, fenix: true);
  }
}
