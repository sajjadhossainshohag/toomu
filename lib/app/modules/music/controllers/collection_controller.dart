import 'package:get/get.dart';

import 'music_controller.dart';

class CollectionController extends GetxController {
  late final MusicCollection collection = Get.arguments as MusicCollection;
  MusicController get music => Get.find<MusicController>();
}
