import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/design_metrics.dart';
import '../../../data/models/video_item.dart';
import '../../../widgets/app_header.dart';
import '../../../widgets/mini_player.dart';
import '../../../widgets/selection_header.dart';
import '../controllers/videos_controller.dart';
import 'widgets/video_tile.dart';

/// Videos of one folder; playing one queues the rest of the folder.
class VideoFolderView extends GetView<VideosController> {
  const VideoFolderView({super.key});

  @override
  Widget build(BuildContext context) {
    // This route's own argument: Get.arguments belongs to the top route (the player's playlist) when this page rebuilds under it.
    final name = (ModalRoute.of(context)!.settings.arguments as VideoFolder).name;
    List<VideoItem> folderVideos() => controller.folders.firstWhereOrNull((f) => f.name == name)?.videos ?? const [];
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            SelectionHeader(
              selection: controller.selection,
              onSelectAll: () => controller.selectAll(folderVideos()),
              onPrivate: controller.moveSelectedToPrivate,
              onDelete: controller.deleteSelected,
              header: () => PageBackHeader(title: name),
            ),
            Expanded(
              child: Obx(() {
                // Looked up again on each change: a video moved to the private folder leaves the list.
                final videos = folderVideos();
                return ListView.builder(
                  padding: EdgeInsets.only(bottom: 24 * context.scale),
                  itemCount: videos.length,
                  itemBuilder: (_, i) => VideoTile(
                    video: videos[i],
                    onTap: () => controller.play(videos, videos[i]),
                    onMenu: () => controller.showMenu(videos[i]),
                    selection: controller.selection,
                  ),
                );
              }),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const SafeArea(top: false, child: MiniPlayer()),
    );
  }
}
