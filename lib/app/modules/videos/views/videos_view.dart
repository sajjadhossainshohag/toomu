import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/design_metrics.dart';
import '../../../widgets/app_header.dart';
import '../../../widgets/app_search_field.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/segmented_tabs.dart';
import '../../../widgets/selection_header.dart';
import '../../../widgets/swipe_tab_view.dart';
import '../../../widgets/top_fade.dart';
import '../../private_folder/controllers/private_folder_controller.dart';
import '../controllers/videos_controller.dart';
import 'widgets/video_tile.dart';

class VideosView extends GetView<VideosController> {
  const VideosView({super.key});

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    return Column(
      children: <Widget>[
        SelectionHeader(
          selection: controller.selection,
          onSelectAll: () => controller.selectAll(controller.videos),
          onPrivate: controller.moveSelectedToPrivate,
          onDelete: controller.deleteSelected,
          header: () => AppHeader(
            title: 'Videos',
            subtitle: '${controller.total} videos on this device',
            actions: <Widget>[
              const HeaderAction(
                icon: Icons.lock_outline_rounded,
                tooltip: 'Private folder',
                onTap: openPrivateFolder,
              ),
              HeaderAction(
                icon: Icons.sort_rounded,
                tooltip: 'Sort',
                onTap: controller.pickSort,
              ),
              HeaderAction(
                icon: Icons.refresh_rounded,
                tooltip: 'Rescan',
                onTap: controller.load,
              ),
            ],
            bottom: AppSearchField(
              hint: 'Search videos and folders',
              onChanged: (v) => controller.query.value = v,
            ),
          ),
        ),
        SizedBox(height: 6 * scale),
        Obx(
          () => SegmentedTabs(
            labels: VideosController.tabs,
            selected: controller.tab.value,
            onSelect: (i) => controller.tab.value = i,
          ),
        ),
        SizedBox(height: 4 * scale),
        Expanded(
          child: Obx(() {
            if (controller.loading.value) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!controller.hasPermission.value) {
              return EmptyState(
                icon: Icons.lock_open_rounded,
                title: 'Allow video access',
                message:
                    'Toomu needs permission to find the videos on your device.',
                actionLabel: 'Grant access',
                onAction: controller.load,
              );
            }
            if (controller.total == 0) {
              return const EmptyState(
                icon: Icons.video_library_rounded,
                title: 'No videos yet',
                message:
                    'Videos on your device and the ones you download appear here.',
              );
            }
            return TopFade(
              child: SwipeTabView(
                index: controller.tab,
                count: VideosController.tabs.length,
                itemBuilder: (_, i) => i == 0 ? _AllVideos() : _Folders(),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _Folders extends GetView<VideosController> {
  @override
  Widget build(BuildContext context) => Obx(() {
    final folders = controller.folders;
    return ListView.builder(
      padding: EdgeInsets.only(
        top: 10 * context.scale,
        bottom: 24 * context.scale,
      ),
      itemCount: folders.length,
      itemBuilder: (_, i) => VideoFolderRow(
        folder: folders[i],
        onTap: () => controller.openFolder(folders[i]),
      ),
    );
  });
}

class _AllVideos extends GetView<VideosController> {
  @override
  Widget build(BuildContext context) => Obx(() {
    final list = controller.videos;
    return ListView.builder(
      padding: EdgeInsets.only(
        top: 6 * context.scale,
        bottom: 24 * context.scale,
      ),
      itemCount: list.length,
      itemBuilder: (_, i) => VideoTile(
        video: list[i],
        onTap: () => controller.play(list, list[i]),
        onMenu: () => controller.showMenu(list[i]),
        selection: controller.selection,
      ),
    );
  });
}
