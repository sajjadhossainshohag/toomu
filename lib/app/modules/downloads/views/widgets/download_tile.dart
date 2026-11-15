import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/theme/color_constants.dart';
import '../../../../core/theme/design_metrics.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../data/models/download_task.dart';
import '../../../../widgets/gradient_progress_bar.dart';
import '../../../../widgets/option_sheet.dart';
import '../../../../widgets/round_icon_button.dart';
import '../../../../widgets/track_artwork.dart';
import '../../controllers/downloads_controller.dart';

class DownloadTile extends StatelessWidget {
  const DownloadTile({required this.task, required this.controller, super.key});

  final DownloadTask task;
  final DownloadsController controller;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final bool dark = context.isDark;
    final Color ink = ColorConstants.textOn(dark);

    return Obx(() {
      final status = task.status.value;
      final done = status == DownloadStatus.completed;

      return Material(
        color: ColorConstants.groupOn(dark),
        borderRadius: BorderRadius.circular(16 * scale),
        child: InkWell(
          borderRadius: BorderRadius.circular(16 * scale),
          onTap: done
              ? () => controller.open(task)
              : () => controller.toggle(task),
          onLongPress: () => _menu(done),
          child: Padding(
            padding: EdgeInsets.all(10 * scale),
            child: Row(
              children: <Widget>[
                _Thumb(url: task.thumbnailUrl, kind: task.kind),
                SizedBox(width: 12 * scale),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        task.title,
                        maxLines: done ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14 * scale,
                          height: 1.3,
                          fontWeight: FontWeight.w700,
                          color: ink,
                        ),
                      ),
                      SizedBox(height: 6 * scale),
                      if (!done) ...<Widget>[
                        GradientProgressBar(
                          value:
                              task.phase.value == DownloadPhase.merging ||
                                  task.phase.value == DownloadPhase.converting
                              ? 1
                              : task.progress,
                          height: 5,
                          color: switch (status) {
                            DownloadStatus.failed => ColorConstants.error,
                            DownloadStatus.paused => ink.withValues(alpha: 0.3),
                            _ => null,
                          },
                        ),
                        SizedBox(height: 6 * scale),
                      ],
                      _StatusLine(task: task, ink: ink),
                    ],
                  ),
                ),
                SizedBox(width: 6 * scale),
                if (done)
                  RoundIconButton(
                    icon: Icons.more_vert_rounded,
                    size: 36,
                    onTap: () => _menu(done),
                  )
                else
                  RoundIconButton(
                    icon: switch (status) {
                      DownloadStatus.running ||
                      DownloadStatus.queued => Icons.pause_rounded,
                      DownloadStatus.failed => Icons.refresh_rounded,
                      _ => Icons.play_arrow_rounded,
                    },
                    size: 40,
                    filled:
                        status != DownloadStatus.paused &&
                        status != DownloadStatus.failed,
                    active:
                        status == DownloadStatus.paused ||
                        status == DownloadStatus.failed,
                    onTap: () => controller.toggle(task),
                  ),
              ],
            ),
          ),
        ),
      );
    });
  }

  Future<void> _menu(bool done) async {
    final action = await showOptionSheet<String>(
      title: task.title,
      options: <SheetOption<String>>[
        if (done) ...const <SheetOption<String>>[
          SheetOption(
            value: 'open',
            label: 'Open',
            icon: Icons.play_circle_outline_rounded,
          ),
          SheetOption(
            value: 'share',
            label: 'Share',
            icon: Icons.share_rounded,
          ),
        ],
        SheetOption(
          value: 'delete',
          label: done ? 'Delete' : 'Cancel download',
          icon: Icons.delete_outline_rounded,
        ),
      ],
    );
    switch (action) {
      case 'open':
        controller.open(task);
      case 'share':
        controller.share(task);
      case 'delete':
        controller.delete(task);
    }
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.task, required this.ink});

  final DownloadTask task;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final status = task.status.value;
    final total = task.totalBytes.value;
    final received = task.receivedBytes.value;

    final phase = task.phase.value;
    final String partLabel = task.needsMerge
        ? (phase == DownloadPhase.audio ? 'Audio • ' : 'Video • ')
        : '';
    final bool preparing =
        status == DownloadStatus.running &&
        (phase == DownloadPhase.lookingUp || phase == DownloadPhase.starting);
    final bool processing =
        preparing ||
        phase == DownloadPhase.merging ||
        phase == DownloadPhase.converting;
    final String left = phase == DownloadPhase.merging
        ? 'Merging video & audio…'
        : phase == DownloadPhase.converting
        ? 'Converting to MP3…'
        : preparing
        ? (phase == DownloadPhase.lookingUp
              ? 'Getting video info…'
              : 'Starting download…')
        : switch (status) {
            DownloadStatus.completed =>
              '${task.qualityLabel} • ${task.extension.toUpperCase()} • ${Formatters.bytes(total)}',
            DownloadStatus.failed => task.error.value ?? 'Failed',
            DownloadStatus.queued => 'Waiting…',
            DownloadStatus.paused =>
              'Paused • ${Formatters.bytes(received)} / ${Formatters.bytes(total)}',
            DownloadStatus.running =>
              '$partLabel${Formatters.bytes(received)} / ${Formatters.bytes(total)}',
            DownloadStatus.canceled => 'Canceled',
          };
    final String? right = status == DownloadStatus.running && !processing
        ? '${Formatters.speed(task.speed.value)} • ${(task.progress * 100).toStringAsFixed(0)}%'
        : null;

    final TextStyle style = TextStyle(
      fontSize: 11.5 * scale,
      fontWeight: FontWeight.w600,
      color: status == DownloadStatus.failed
          ? ColorConstants.error
          : ink.withValues(alpha: 0.55),
    );
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            left,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        if (right != null) Text(right, style: style),
      ],
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url, required this.kind});

  final String url;
  final DownloadKind kind;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final IconData icon = switch (kind) {
      DownloadKind.audio => Icons.music_note_rounded,
      DownloadKind.video => Icons.movie_rounded,
      DownloadKind.file => Icons.insert_drive_file_rounded,
    };
    return ClipRRect(
      borderRadius: BorderRadius.circular(12 * scale),
      child: SizedBox(
        width: 84 * scale,
        height: 56 * scale,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            url.isEmpty
                ? ArtworkPlaceholder(size: 84, radius: 0, icon: icon)
                : CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    memCacheWidth: (84 * scale * MediaQuery.devicePixelRatioOf(context)).round(),
                    errorWidget: (_, _, _) =>
                        ArtworkPlaceholder(size: 84, radius: 0, icon: icon),
                  ),
            Positioned(
              left: 4 * scale,
              bottom: 4 * scale,
              child: Container(
                padding: EdgeInsets.all(3 * scale),
                decoration: BoxDecoration(
                  color: ColorConstants.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(6 * scale),
                ),
                child: Icon(
                  icon,
                  size: 12 * scale,
                  color: ColorConstants.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
