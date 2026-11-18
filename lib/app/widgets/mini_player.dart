import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../core/theme/brand_colors.dart';
import '../core/theme/color_constants.dart';
import '../core/theme/design_metrics.dart';
import '../routes/app_pages.dart';
import '../data/providers/local_video_provider.dart';
import '../services/audio_player_service.dart';
import '../services/video_session_service.dart';
import 'round_icon_button.dart';
import 'track_artwork.dart';
import '../core/utils/formatters.dart';

/// Persistent now-playing bar shown above the bottom nav.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final AudioPlayerService audio = AudioPlayerService.to;
    final double scale = context.scale;
    final bool dark = context.isDark;
    final Color ink = ColorConstants.textOn(dark);

    return Obx(() {
      // A video playing in the background takes the mini bar's place.
      if (VideoSessionService.to.inBackground.value) return const _VideoMiniBar();
      final track = audio.current;
      if (track == null) return const SizedBox.shrink();

      return GestureDetector(
        onTap: () => Get.toNamed(Routes.player),
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) < -200) Get.toNamed(Routes.player);
        },
        child: Container(
          margin: EdgeInsets.fromLTRB(16 * scale, 0, 16 * scale, 8 * scale),
          decoration: BoxDecoration(
            color: ColorConstants.surfaceOn(dark),
            borderRadius: BorderRadius.circular(16 * scale),
            border: Border.all(color: ink.withValues(alpha: dark ? 0.08 : 0.04)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: BrandColors.of(context).primary.withValues(alpha: 0.12),
                blurRadius: 20 * scale,
                offset: Offset(0, 6 * scale),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16 * scale),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: EdgeInsets.fromLTRB(8 * scale, 8 * scale, 6 * scale, 8 * scale),
                  child: Row(
                    children: <Widget>[
                      Hero(
                        tag: 'now-playing-art',
                        child: TrackArtwork(track: track, size: 44, radius: 12),
                      ),
                      SizedBox(width: 12 * scale),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14 * scale,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0,
                                color: ink,
                              ),
                            ),
                            SizedBox(height: 2 * scale),
                            Text(
                              track.subtitle ?? Formatters.duration(track.duration),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12 * scale,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0,
                                color: ink.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                      RoundIconButton(icon: Icons.skip_previous_rounded, size: 36, onTap: audio.previous),
                      RoundIconButton(
                        icon: audio.playing.value ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        size: 40,
                        filled: true,
                        onTap: audio.togglePlay,
                      ),
                      RoundIconButton(icon: Icons.skip_next_rounded, size: 36, onTap: audio.next),
                      RoundIconButton(icon: Icons.close_rounded, size: 32, onTap: audio.close, tooltip: 'Close'),
                    ],
                  ),
                ),
                SizedBox(
                  height: 2.5 * scale,
                  // Position ticks several times a second: only the bar rebuilds, and its own layer keeps the repaint
                  // from spreading to the whole screen behind it.
                  child: RepaintBoundary(
                    child: Obx(() {
                      final total = audio.duration.value.inMilliseconds;
                      final progress = total <= 0 ? 0.0 : audio.position.value.inMilliseconds / total;
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: progress.clamp(0, 1).toDouble(),
                          child: DecoratedBox(
                            decoration: BoxDecoration(gradient: BrandColors.of(context).progressGradient),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

/// Video audio playing in the background (background play): tap to return
/// to the player, play/pause, or close.
class _VideoMiniBar extends StatelessWidget {
  const _VideoMiniBar();

  @override
  Widget build(BuildContext context) {
    final session = VideoSessionService.to;
    final double scale = context.scale;
    final bool dark = context.isDark;
    final Color ink = ColorConstants.textOn(dark);
    final item = session.current;
    if (item == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: session.reopen,
      child: Container(
        margin: EdgeInsets.fromLTRB(16 * scale, 0, 16 * scale, 8 * scale),
        padding: EdgeInsets.fromLTRB(8 * scale, 8 * scale, 6 * scale, 8 * scale),
        decoration: BoxDecoration(
          color: ColorConstants.surfaceOn(dark),
          borderRadius: BorderRadius.circular(16 * scale),
          border: Border.all(color: ink.withValues(alpha: dark ? 0.08 : 0.04)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: BrandColors.of(context).primary.withValues(alpha: 0.12),
              blurRadius: 20 * scale,
              offset: Offset(0, 6 * scale),
            ),
          ],
        ),
        child: Row(
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(10 * scale),
              child: SizedBox(
                width: 64 * scale,
                height: 40 * scale,
                child: item.id == null
                    ? (item.thumbnailUrl == null
                          ? const ArtworkPlaceholder(size: 64, radius: 0, icon: Icons.movie_rounded)
                          : CachedNetworkImage(
                              imageUrl: item.thumbnailUrl!,
                              fit: BoxFit.cover,
                              memCacheWidth: (64 * scale * MediaQuery.devicePixelRatioOf(context)).round(),
                              errorWidget: (_, _, _) =>
                                  const ArtworkPlaceholder(size: 64, radius: 0, icon: Icons.movie_rounded),
                            ))
                    : FutureBuilder<Uint8List?>(
                        future: VideoThumbCache.load(item.id!),
                        builder: (_, snap) => snap.data == null
                            ? const ArtworkPlaceholder(size: 64, radius: 0, icon: Icons.movie_rounded)
                            : Image.memory(snap.data!, fit: BoxFit.cover, gaplessPlayback: true),
                      ),
              ),
            ),
            SizedBox(width: 12 * scale),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14 * scale, fontWeight: FontWeight.w700, color: ink),
                  ),
                  SizedBox(height: 2 * scale),
                  Text(
                    item.isStream ? 'YouTube · playing in background' : 'Video · playing in background',
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 12 * scale,
                      fontWeight: FontWeight.w500,
                      color: ink.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            Obx(
              () => RoundIconButton(
                icon: session.playing.value ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 40,
                filled: true,
                onTap: () => session.player.playOrPause(),
              ),
            ),
            RoundIconButton(icon: Icons.close_rounded, size: 36, onTap: session.stop, tooltip: 'Stop'),
          ],
        ),
      ),
    );
  }
}
