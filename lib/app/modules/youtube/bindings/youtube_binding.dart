import 'package:get/get.dart';

import '../controllers/youtube_controller.dart';

/// Used when the module is opened as its own route (e.g. from a share
/// intent in the future). Inside the home shell, [HomeBinding] provides it.
class YoutubeBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<YoutubeController>(YoutubeController.new);
  }
}
