import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/theme/color_constants.dart';
import '../../../../core/theme/design_metrics.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../data/models/video_item.dart';
import '../../../../data/providers/local_video_provider.dart';
import '../../../../data/repositories/video_resume_repository.dart';
import '../../../../widgets/app_group.dart';
import '../../../../widgets/track_artwork.dart';
import '../../controllers/videos_controller.dart';

/// Thumbnail with duration badge and watched-progress bar, title, details.
class VideoTile extends StatelessWidget {
  const VideoTile({required this.video, required this.onTap, super.key});

  final VideoItem video;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final Color ink = ColorConstants.textOn(context.isDark);
    final details = [
      video.quality,
      if (video.size > 0) Formatters.bytes(video.size),
    ].whereType<String>().join(' • ');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 16 * scale,
          vertical: 7 * scale,
        ),
        child: Row(
          children: <Widget>[
            _Thumb(video: video),
            SizedBox(width: 12 * scale),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5 * scale,
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                  if (details.isNotEmpty) ...<Widget>[
                    SizedBox(height: 3 * scale),
                    Text(
                      details,
                      style: TextStyle(
                        fontSize: 11.5 * scale,
                        fontWeight: FontWeight.w500,
                        color: ink.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.video});

  final VideoItem video;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final double w = 128 * scale, h = 72 * scale;
    const placeholder = ArtworkPlaceholder(
      size: 128,
      radius: 0,
      icon: Icons.movie_rounded,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(10 * scale),
      child: SizedBox(
        width: w,
        height: h,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ColoredBox(color: ColorConstants.black.withValues(alpha: 0.2)),
            if (video.id != null)
              FutureBuilder<Uint8List?>(
                future: VideoThumbCache.load(video.id!),
                builder: (_, snap) => snap.data == null
                    ? placeholder
                    : Image.memory(
                        snap.data!,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      ),
              )
            else
              placeholder,
            if (video.duration != null)
              Positioned(
                right: 5 * scale,
                bottom: 6 * scale,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 5 * scale,
                    vertical: 1.5 * scale,
                  ),
                  decoration: BoxDecoration(
                    color: ColorConstants.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(5 * scale),
                  ),
                  child: Text(
                    Formatters.duration(video.duration),
                    style: TextStyle(
                      fontSize: 10 * scale,
                      fontWeight: FontWeight.w700,
                      color: ColorConstants.white,
                    ),
                  ),
                ),
              ),
            // Watched-so-far bar (refreshes when returning from the player).
            Obx(() {
              if (Get.isRegistered<VideosController>()) {
                Get.find<VideosController>().watchedVersion.value;
              }
              final p = VideoResumeRepository.instance.progressOf(
                video.resumeKey,
                video.duration,
              );
              if (p == null) return const SizedBox.shrink();
              return Align(
                alignment: Alignment.bottomLeft,
                child: FractionallySizedBox(
                  widthFactor: p,
                  child: Container(
                    height: 3 * scale,
                    color: ColorConstants.error,
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// Folder row: tinted glyph, name, count and total size.
class VideoFolderRow extends StatelessWidget {
  const VideoFolderRow({required this.folder, required this.onTap, super.key});

  final VideoFolder folder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final Color ink = ColorConstants.textOn(context.isDark);
    final n = folder.videos.length;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 16 * scale,
          vertical: 9 * scale,
        ),
        child: Row(
          children: <Widget>[
            GlyphTile(
              icon: Icons.folder_rounded,
              tint: ColorConstants.tileFolder,
              size: 44,
            ),
            SizedBox(width: 14 * scale),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    folder.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14 * scale,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                  Text(
                    '$n video${n == 1 ? '' : 's'} • ${Formatters.bytes(folder.totalBytes)}',
                    style: TextStyle(
                      fontSize: 12 * scale,
                      fontWeight: FontWeight.w500,
                      color: ink.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: ink.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }
}
