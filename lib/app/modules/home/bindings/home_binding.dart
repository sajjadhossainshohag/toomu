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
    Get.lazyPut<HomeController>(HomeController.new);
    Get.lazyPut<YoutubeController>(YoutubeController.new);
    Get.lazyPut<DownloadsController>(DownloadsController.new);
    Get.lazyPut<MusicController>(MusicController.new);
    Get.lazyPut<VideosController>(VideosController.new);
    Get.lazyPut<SettingsController>(SettingsController.new);
  }
}
