import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/theme/brand_colors.dart';
import '../../../../core/theme/color_constants.dart';
import '../../../../core/theme/design_metrics.dart';
import '../../../../services/audio_player_service.dart';
import '../../../../widgets/option_sheet.dart';
import '../../../../widgets/round_icon_button.dart';
import '../../../../widgets/track_artwork.dart';
import '../../../../core/utils/formatters.dart';

/// Reorderable play queue (drag handle to move, swipe to remove).
class QueueSheet extends StatelessWidget {
  const QueueSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final audio = AudioPlayerService.to;
    final double scale = context.scale;
    final Color ink = ColorConstants.textOn(context.isDark);
    final BrandColors brand = BrandColors.of(context);

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
      child: AppSheet(
        title: 'Up next',
        // The rows are built during layout, after this Obx ran: the playing index is read here, where it is watched.
        child: Obx(() {
          final playing = audio.currentIndex.value;
          return ReorderableListView.builder(
            shrinkWrap: true,
            buildDefaultDragHandles: false,
            itemCount: audio.queue.length,
            onReorder: (from, to) => audio.move(from, to > from ? to - 1 : to),
            itemBuilder: (_, i) {
              final t = audio.queue[i];
              final current = i == playing;
              return Dismissible(
                key: ValueKey('${t.id}#$i'),
                direction: current ? DismissDirection.none : DismissDirection.endToStart,
                onDismissed: (_) => audio.removeAt(i),
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: EdgeInsets.only(right: 20 * scale),
                  color: ColorConstants.error.withValues(alpha: 0.15),
                  child: const Icon(Icons.delete_outline_rounded, color: ColorConstants.error),
                ),
                child: InkWell(
                  onTap: () => audio.skipTo(i),
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 6 * scale),
                    child: Row(
                      children: <Widget>[
                        TrackArtwork(track: t, size: 44, radius: 12),
                        SizedBox(width: 12 * scale),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                t.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14 * scale,
                                  fontWeight: FontWeight.w700,
                                  color: current
                                      ? (context.isDark ? brand.accent : brand.primary)
                                      : ink,
                                ),
                              ),
                              Text(
                                t.subtitle ?? Formatters.duration(t.duration),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12 * scale,
                                  fontWeight: FontWeight.w500,
                                  color: ink.withValues(alpha: 0.55),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (current)
                          Icon(Icons.graphic_eq_rounded, size: 20 * scale, color: brand.primary),
                        ReorderableDragStartListener(
                          index: i,
                          child: RoundIconButton(
                            icon: Icons.drag_handle_rounded,
                            size: 36,
                            onTap: null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}
