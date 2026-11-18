import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../../../core/theme/color_constants.dart';
import '../../../../core/theme/design_metrics.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../widgets/press_start.dart';
import '../../../../widgets/track_artwork.dart';

class VideoCard extends StatelessWidget {
  const VideoCard({
    required this.video,
    required this.onTap,
    this.onMore,
    this.onPressStart,
    super.key,
  });

  final Video video;

  /// The card: watch it (no ads).
  final VoidCallback onTap;

  /// ⋮: Download, Share, Copy link.
  final VoidCallback? onMore;
  final VoidCallback? onPressStart;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final bool dark = context.isDark;
    final Color ink = ColorConstants.textOn(dark);

    final card = GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: ColorConstants.groupOn(dark),
          borderRadius: BorderRadius.circular(16 * scale),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  CachedNetworkImage(
                    imageUrl: video.thumbnails.highResUrl,
                    fit: BoxFit.cover,
                    // The 1280 px original decoded at full size took ~3.5 MB of RAM per card.
                    memCacheWidth: math.min(1280, (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context)).round()),
                    placeholder: (_, _) =>
                        const ArtworkPlaceholder(size: 375, radius: 0, icon: Icons.smart_display_rounded),
                    errorWidget: (_, _, _) =>
                        const ArtworkPlaceholder(size: 375, radius: 0, icon: Icons.smart_display_rounded),
                  ),
                  if (video.duration != null)
                    Positioned(
                      right: 10 * scale,
                      bottom: 10 * scale,
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 3 * scale),
                        decoration: BoxDecoration(
                          color: ColorConstants.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(8 * scale),
                        ),
                        child: Text(
                          Formatters.duration(video.duration),
                          style: TextStyle(
                            fontSize: 11 * scale,
                            fontWeight: FontWeight.w700,
                            color: ColorConstants.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(14 * scale, 12 * scale, 10 * scale, 12 * scale),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          video.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14 * scale,
                            height: 1.3,
                            fontWeight: FontWeight.w700,
                            color: ink,
                          ),
                        ),
                        SizedBox(height: 4 * scale),
                        Text(
                          [
                            video.author,
                            if (video.engagement.viewCount > 0)
                              '${Formatters.compact(video.engagement.viewCount)} views',
                            if (video.uploadDateRaw != null) video.uploadDateRaw!,
                          ].join(' • '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12 * scale,
                            fontWeight: FontWeight.w500,
                            color: ink.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onMore != null)
                    IconButton(
                      tooltip: 'More',
                      onPressed: onMore,
                      icon: Icon(Icons.more_vert_rounded, color: ink.withValues(alpha: 0.7)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return onPressStart == null ? card : PressStart(onStart: onPressStart!, child: card);
  }
}
