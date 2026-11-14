import 'package:get/get.dart';

import '../controllers/videos_controller.dart';

/// Inside the home shell, HomeBinding provides this; used when the module
/// is opened as its own route.
class VideosBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<VideosController>()) Get.lazyPut<VideosController>(VideosController.new);
  }
}
