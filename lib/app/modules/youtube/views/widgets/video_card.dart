import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../../../core/theme/color_constants.dart';
import '../../../../core/theme/design_metrics.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../widgets/press_start.dart';
import '../../../../widgets/round_icon_button.dart';
import '../../../../widgets/track_artwork.dart';

class VideoCard extends StatelessWidget {
  const VideoCard({
    required this.video,
    required this.onTap,
    this.onWatch,
    this.onPressStart,
    this.watchLoading = false,
    super.key,
  });

  final Video video;

  /// Card / ⬇ button: the download sheet.
  final VoidCallback onTap;

  /// ▶ button: watch in the app's player (no ads).
  final VoidCallback? onWatch;
  final VoidCallback? onPressStart;
  final bool watchLoading;

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
                  SizedBox(width: 8 * scale),
                  if (onWatch != null) ...<Widget>[
                    watchLoading
                        ? SizedBox(
                            width: 42 * scale,
                            height: 42 * scale,
                            child: Padding(
                              padding: EdgeInsets.all(11 * scale),
                              child: const CircularProgressIndicator(strokeWidth: 2.5),
                            ),
                          )
                        : RoundIconButton(
                            icon: Icons.play_arrow_rounded,
                            size: 42,
                            filled: true,
                            gradient: ColorConstants.watchGradient,
                            onTap: onWatch,
                            tooltip: 'Watch',
                          ),
                    SizedBox(width: 8 * scale),
                  ],
                  RoundIconButton(
                    icon: Icons.download_rounded,
                    size: 42,
                    filled: true,
                    onTap: onTap,
                    tooltip: 'Download',
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
