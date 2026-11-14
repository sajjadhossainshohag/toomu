import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/theme/color_constants.dart';
import '../../../../core/theme/design_metrics.dart';
import '../../../../widgets/app_group.dart';
import '../../../../widgets/track_artwork.dart';
import '../../controllers/music_controller.dart';

/// Grid card for albums.
class AlbumCard extends StatelessWidget {
  const AlbumCard({required this.collection, required this.onTap, super.key});

  final MusicCollection collection;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final Color ink = ColorConstants.textOn(context.isDark);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(8 * scale),
        decoration: BoxDecoration(
          color: ColorConstants.groupOn(context.isDark),
          borderRadius: BorderRadius.circular(16 * scale),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            LayoutBuilder(
              builder: (_, c) => TrackArtwork(
                track: collection.tracks.first,
                size: c.maxWidth / scale,
                radius: 12,
                highRes: true,
              ),
            ),
            SizedBox(height: 8 * scale),
            Text(
              collection.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13 * scale,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
            Text(
              collection.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5 * scale,
                fontWeight: FontWeight.w500,
                color: ink.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// List row for artists / folders: tinted glyph tile + chevron.
class CollectionRow extends StatelessWidget {
  const CollectionRow({
    required this.collection,
    required this.icon,
    required this.tint,
    required this.onTap,
    super.key,
  });

  final MusicCollection collection;
  final IconData icon;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final Color ink = ColorConstants.textOn(context.isDark);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 16 * scale,
          vertical: 9 * scale,
        ),
        child: Row(
          children: <Widget>[
            GlyphTile(icon: icon, tint: tint, size: 44),
            SizedBox(width: 14 * scale),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    collection.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14 * scale,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                  Text(
                    collection.subtitle,
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
            SvgPicture.asset(
              'assets/icons/settings_chevron.svg',
              width: 18 * scale,
              height: 18 * scale,
              colorFilter: const ColorFilter.mode(
                ColorConstants.chevron,
                BlendMode.srcIn,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
