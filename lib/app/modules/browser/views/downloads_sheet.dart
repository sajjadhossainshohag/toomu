import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/brand_colors.dart';
import '../../../core/theme/color_constants.dart';
import '../../../core/theme/design_metrics.dart';
import '../../../widgets/app_snackbar.dart';
import '../../../widgets/option_sheet.dart';
import '../../../widgets/round_icon_button.dart';
import '../../downloads/controllers/downloads_controller.dart';
import '../../downloads/views/widgets/download_tile.dart';

class BrowserDownloadsButton extends StatelessWidget {
  const BrowserDownloadsButton({super.key});

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final downloads = Get.find<DownloadsController>();
    return Obx(() {
      final running = downloads.tasks.where((t) => t.isActive).toList();
      final total = running.fold<int>(0, (s, t) => s + t.totalBytes.value);
      final got = running.fold<int>(0, (s, t) => s + t.receivedBytes.value);
      return Stack(
        alignment: Alignment.center,
        children: <Widget>[
          RoundIconButton(
            icon: Icons.download_rounded,
            size: 40,
            active: running.isNotEmpty,
            onTap: showDownloadsSheet,
            tooltip: 'Downloads',
          ),
          if (running.isNotEmpty)
            IgnorePointer(
              child: SizedBox.square(
                dimension: 36 * scale,
                child: CircularProgressIndicator(
                  value: total > 0 ? (got / total).clamp(0.0, 1.0) : 0,
                  strokeWidth: 2.5 * scale,
                  color: BrandColors.of(context).primary,
                ),
              ),
            ),
        ],
      );
    });
  }
}

void showDownloadsSheet() => Get.bottomSheet<void>(const _DownloadsSheet(), isScrollControlled: true);

void showDownloadStarted(String name) => showSnack(
      'Download started',
      name,
      duration: const Duration(seconds: 4),
      mainButton: TextButton(
        onPressed: () {
          Get.closeCurrentSnackbar();
          showDownloadsSheet();
        },
        child: const Text('View'),
      ),
    );

class _DownloadsSheet extends StatelessWidget {
  const _DownloadsSheet();

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final c = Get.find<DownloadsController>();
    return AppSheet(
      title: 'Downloads',
      child: Obx(() {
        final items = [...c.active, ...c.completed];
        if (items.isEmpty) {
          return Padding(
            padding: EdgeInsets.symmetric(vertical: 24 * scale),
            child: Text(
              'No downloads yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14 * scale,
                color: ColorConstants.textOn(context.isDark).withValues(alpha: 0.6),
              ),
            ),
          );
        }
        return ListView.separated(
          shrinkWrap: true,
          itemCount: items.length,
          separatorBuilder: (_, _) => SizedBox(height: 10 * scale),
          itemBuilder: (_, i) => DownloadTile(key: ValueKey(items[i].id), task: items[i], controller: c),
        );
      }),
    );
  }
}
