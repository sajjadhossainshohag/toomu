import 'package:get/get.dart';

import '../../youtube/controllers/youtube_controller.dart';
import '../controllers/channel_controller.dart';

class ChannelBinding extends Bindings {
  @override
  void dependencies() {
    final args = Get.arguments as ChannelArgs;
    // One per channel: a channel page opened over another one would otherwise get the first one's controller.
    Get.lazyPut<ChannelController>(
      () => ChannelController(args, Get.find<YoutubeController>().channelSource),
      tag: args.id,
    );
  }
}
