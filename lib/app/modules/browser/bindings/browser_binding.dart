import 'package:get/get.dart';

import '../../youtube/controllers/youtube_controller.dart';
import '../controllers/browser_controller.dart';

class BrowserBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<BrowserController>(BrowserController.new);
    // The YouTube format sheet needs this; normally HomeBinding provides it.
    if (!Get.isRegistered<YoutubeController>()) {
      Get.lazyPut<YoutubeController>(YoutubeController.new);
    }
  }
}
