import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../../../core/theme/color_constants.dart';
import '../../../../core/theme/design_metrics.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../widgets/track_artwork.dart';

/// A video as a row: thumbnail on the left, title and channel on the right (Up next, a channel's videos).
class VideoRow extends StatelessWidget {
  const VideoRow({required this.video, required this.onTap, this.loading = false, super.key});

  final Video video;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final Color ink = ColorConstants.textOn(context.isDark);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 6 * scale),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(10 * scale),
              child: SizedBox(
                width: 160 * scale,
                height: 90 * scale,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    CachedNetworkImage(
                      imageUrl: video.thumbnails.mediumResUrl,
                      fit: BoxFit.cover,
                      memCacheWidth: (160 * scale * MediaQuery.devicePixelRatioOf(context)).round(),
                      placeholder: (_, _) => const ArtworkPlaceholder(size: 160, radius: 0, icon: Icons.smart_display_rounded),
                      errorWidget: (_, _, _) => const ArtworkPlaceholder(size: 160, radius: 0, icon: Icons.smart_display_rounded),
                    ),
                    if (video.duration != null)
                      Positioned(
                        right: 6 * scale,
                        bottom: 6 * scale,
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 5 * scale, vertical: 2 * scale),
                          decoration: BoxDecoration(color: ColorConstants.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(6 * scale)),
                          child: Text(
                            Formatters.duration(video.duration),
                            style: TextStyle(fontSize: 10.5 * scale, fontWeight: FontWeight.w700, color: ColorConstants.white),
                          ),
                        ),
                      ),
                    if (loading)
                      ColoredBox(
                        color: ColorConstants.black.withValues(alpha: 0.45),
                        child: const Center(child: CircularProgressIndicator(color: ColorConstants.white)),
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(width: 12 * scale),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5 * scale, height: 1.3, fontWeight: FontWeight.w700, color: ink),
                  ),
                  SizedBox(height: 4 * scale),
                  Text(
                    [
                      video.author,
                      if (video.engagement.viewCount > 0) '${Formatters.compact(video.engagement.viewCount)} views',
                    ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12 * scale, color: ink.withValues(alpha: 0.6)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

