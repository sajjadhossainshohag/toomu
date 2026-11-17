import 'package:get/get.dart';

import '../../youtube/controllers/youtube_controller.dart';
import '../controllers/browser_session.dart';

class BrowserBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<BrowserSession>(BrowserSession.new);
    // The YouTube format sheet needs this; normally HomeBinding provides it.
    if (!Get.isRegistered<YoutubeController>()) {
      Get.lazyPut<YoutubeController>(YoutubeController.new);
    }
  }
}
