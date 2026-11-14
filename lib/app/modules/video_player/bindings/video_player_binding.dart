import 'package:get/get.dart';

import '../controllers/video_playback_controller.dart';

class VideoPlayerBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<VideoPlaybackController>(VideoPlaybackController.new);
  }
}
