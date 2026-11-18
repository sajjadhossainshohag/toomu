import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../../../core/theme/color_constants.dart';
import '../../../../core/theme/design_metrics.dart';
import '../../../../widgets/track_artwork.dart';

class ShortsShelf extends StatelessWidget {
  const ShortsShelf({required this.shorts, required this.onTap, super.key});

  final List<Video> shorts;
  final void Function(int index) onTap;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final double width = 124 * scale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.slow_motion_video_rounded, size: 20 * scale, color: ColorConstants.primary),
            SizedBox(width: 8 * scale),
            Text(
              'Shorts',
              style: TextStyle(
                fontSize: 16 * scale,
                fontWeight: FontWeight.w800,
                color: ColorConstants.textOn(context.isDark),
              ),
            ),
          ],
        ),
        SizedBox(height: 10 * scale),
        LayoutBuilder(
          // The feed is padded; the shelf runs edge to edge like YouTube's.
          builder: (_, c) => SizedBox(
            height: width * 16 / 9,
            child: OverflowBox(
              maxWidth: c.maxWidth + 2 * DesignMetrics.gutter * scale,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: DesignMetrics.gutter * scale),
                itemCount: shorts.length,
                separatorBuilder: (_, _) => SizedBox(width: 8 * scale),
                itemBuilder: (_, i) => SizedBox(
                  width: width,
                  child: ShortTile(video: shorts[i], onTap: () => onTap(i)),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class ShortTile extends StatelessWidget {
  const ShortTile({super.key, required this.video, required this.onTap});

  final Video video;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    return Material(
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(12 * scale),
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            CachedNetworkImage(
              imageUrl: video.thumbnails.highResUrl,
              fit: BoxFit.cover,
              memCacheWidth: (120 * scale * MediaQuery.devicePixelRatioOf(context)).round(),
              placeholder: (_, _) => const ArtworkPlaceholder(size: 120, radius: 0, icon: Icons.smart_display_rounded),
              errorWidget: (_, _, _) =>
                  const ArtworkPlaceholder(size: 120, radius: 0, icon: Icons.smart_display_rounded),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Color(0x00000000), Color(0xB3000000)],
                  stops: <double>[0.55, 1],
                ),
              ),
            ),
            Positioned(
              left: 8 * scale,
              right: 8 * scale,
              bottom: 8 * scale,
              child: Text(
                video.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12 * scale,
                  height: 1.25,
                  fontWeight: FontWeight.w700,
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
