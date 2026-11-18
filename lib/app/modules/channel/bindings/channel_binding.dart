import 'package:get/get.dart';

import '../../youtube/controllers/youtube_controller.dart';
import '../controllers/channel_controller.dart';

class ChannelBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ChannelController>(
      () => ChannelController(Get.arguments as ChannelArgs, Get.find<YoutubeController>().channelSource),
    );
  }
}
