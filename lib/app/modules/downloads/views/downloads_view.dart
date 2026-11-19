import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/design_metrics.dart';
import '../../../widgets/app_header.dart';
import '../../../widgets/empty_state.dart';
import '../../../data/models/download_task.dart';
import '../../../widgets/segmented_tabs.dart';
import '../../../widgets/selection_header.dart';
import '../../../widgets/swipe_tab_view.dart';
import '../../../widgets/top_fade.dart';
import '../../home/controllers/home_controller.dart';
import '../../home/home_tabs.dart';
import '../controllers/downloads_controller.dart';
import 'widgets/download_tile.dart';

class DownloadsView extends GetView<DownloadsController> {
  const DownloadsView({super.key});

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;

    return Obx(() {
      final active = controller.active;
      final completed = controller.completed;
      final showingActive = controller.tab.value == 0;

      return Column(
        children: <Widget>[
          SelectionHeader(
            selection: controller.selection,
            onSelectAll: controller.selectAll,
            onPrivate: controller.moveSelectedToPrivate,
            onDelete: controller.deleteSelected,
            header: () => AppHeader(
              title: 'Downloads',
              subtitle:
                  '${active.length} in progress · ${completed.length} completed',
              actions: <Widget>[
                if (showingActive && active.isNotEmpty)
                  HeaderAction(
                    icon: controller.anyRunning
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    tooltip: controller.anyRunning ? 'Pause all' : 'Resume all',
                    onTap: controller.anyRunning
                        ? controller.pauseAll
                        : controller.resumeAll,
                  ),
                if (!showingActive && completed.isNotEmpty)
                  HeaderAction(
                    icon: Icons.delete_sweep_rounded,
                    tooltip: 'Clear completed',
                    onTap: controller.clearCompleted,
                  ),
              ],
            ),
          ),
          SizedBox(height: 4 * scale),
          SegmentedTabs(
            labels: <String>[
              'Downloading (${active.length})',
              'Completed (${completed.length})',
            ],
            selected: controller.tab.value,
            onSelect: (i) => controller.tab.value = i,
          ),
          SizedBox(height: 4 * scale),
          Expanded(
            child: SwipeTabView(
              index: controller.tab,
              count: 2,
              itemBuilder: (_, i) => Obx(
                () => _list(
                  i == 0 ? controller.active : controller.completed,
                  active: i == 0,
                ),
              ),
            ),
          ),
        ],
      );
    });
  }

  Widget _list(List<DownloadTask> items, {required bool active}) {
    final double scale = Get.context!.scale;
    if (items.isEmpty) {
      return EmptyState(
        icon: active
            ? Icons.cloud_download_rounded
            : Icons.download_done_rounded,
        title: active ? 'No active downloads' : 'Nothing here yet',
        message: active
            ? 'Search YouTube or paste a link to start downloading.'
            : 'Finished downloads will appear here.',
        actionLabel: 'Find something',
        onAction: () => Get.find<HomeController>().openTab(HomeTabs.youtube),
      );
    }
    return TopFade(
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(
          16 * scale,
          16 * scale,
          16 * scale,
          24 * scale,
        ),
        itemCount: items.length,
        separatorBuilder: (_, _) => SizedBox(height: 10 * scale),
        itemBuilder: (_, i) => DownloadTile(
          key: ValueKey(items[i].id),
          task: items[i],
          controller: controller,
          selection: controller.selection,
        ),
      ),
    );
  }
}
