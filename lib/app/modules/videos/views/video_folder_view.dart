import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/design_metrics.dart';
import '../../../widgets/app_header.dart';
import '../../../widgets/mini_player.dart';
import '../controllers/videos_controller.dart';
import 'widgets/video_tile.dart';

/// Videos of one folder; playing one queues the rest of the folder.
class VideoFolderView extends GetView<VideosController> {
  const VideoFolderView({super.key});

  @override
  Widget build(BuildContext context) {
    final folder = Get.arguments as VideoFolder;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            PageBackHeader(title: folder.name),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.only(bottom: 24 * context.scale),
                itemCount: folder.videos.length,
                itemBuilder: (_, i) => VideoTile(
                  video: folder.videos[i],
                  onTap: () => controller.play(folder.videos, folder.videos[i]),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const SafeArea(top: false, child: MiniPlayer()),
    );
  }
}
