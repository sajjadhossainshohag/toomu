import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/theme/brand_colors.dart';
import '../core/theme/color_constants.dart';
import '../core/theme/design_metrics.dart';
import '../data/models/track.dart';
import '../data/providers/local_music_provider.dart';

/// Track cover: embedded art → network thumbnail → gradient placeholder.
class TrackArtwork extends StatelessWidget {
  const TrackArtwork({
    required this.track,
    this.size = 48,
    this.radius = 12,
    this.highRes = false,
    super.key,
  });

  final Track? track;
  final double size;
  final double radius;
  final bool highRes;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final double s = size * scale;
    final BorderRadius r = BorderRadius.circular(radius * scale);
    final Widget placeholder = ArtworkPlaceholder(size: size, radius: radius);
    final Track? t = track;

    Widget child;
    if (t?.artworkUrl != null) {
      child = CachedNetworkImage(
        imageUrl: t!.artworkUrl!,
        width: s,
        height: s,
        fit: BoxFit.cover,
        memCacheWidth: (s * MediaQuery.devicePixelRatioOf(context)).round(),
        placeholder: (_, _) => placeholder,
        errorWidget: (_, _, _) => placeholder,
      );
    } else if (t?.localSongId != null) {
      child = FutureBuilder<Uint8List?>(
        future: ArtworkCache.load(t!.localSongId!, size: highRes ? 720 : 200),
        builder: (_, snap) {
          final bytes = snap.data;
          if (bytes == null || bytes.isEmpty) return placeholder;
          return Image.memory(
            bytes,
            width: s,
            height: s,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => placeholder,
          );
        },
      );
    } else {
      child = placeholder;
    }
    return ClipRRect(borderRadius: r, child: SizedBox.square(dimension: s, child: child));
  }
}

class ArtworkPlaceholder extends StatelessWidget {
  const ArtworkPlaceholder({this.size = 48, this.radius = 12, this.icon, super.key});

  final double size;
  final double radius;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    return Container(
      width: size * scale,
      height: size * scale,
      decoration: BoxDecoration(
        gradient: BrandColors.of(context).badgeGradient,
        borderRadius: BorderRadius.circular(radius * scale),
      ),
      child: Icon(
        icon ?? Icons.music_note_rounded,
        size: size * 0.45 * scale,
        color: ColorConstants.white.withValues(alpha: 0.95),
      ),
    );
  }
}
