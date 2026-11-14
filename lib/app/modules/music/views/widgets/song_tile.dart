import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/theme/brand_colors.dart';
import '../../../../core/theme/color_constants.dart';
import '../../../../core/theme/design_metrics.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../data/models/track.dart';
import '../../../../services/audio_player_service.dart';
import '../../../../widgets/option_sheet.dart';
import '../../../../widgets/round_icon_button.dart';
import '../../../../widgets/track_artwork.dart';
import '../../controllers/music_controller.dart';

class SongTile extends StatelessWidget {
  const SongTile({required this.track, required this.onTap, super.key});

  final Track track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final Color ink = ColorConstants.textOn(context.isDark);
    final BrandColors brand = BrandColors.of(context);
    final audio = AudioPlayerService.to;

    return Obx(() {
      final bool current = audio.current?.id == track.id;
      final Color titleColor = current
          ? (context.isDark ? brand.accent : brand.primary)
          : ink;
      return InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16 * scale,
            7 * scale,
            6 * scale,
            7 * scale,
          ),
          child: Row(
            children: <Widget>[
              Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  TrackArtwork(track: track, size: 48, radius: 12),
                  if (current)
                    Container(
                      width: 48 * scale,
                      height: 48 * scale,
                      decoration: BoxDecoration(
                        color: ColorConstants.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(12 * scale),
                      ),
                      child: Icon(
                        audio.playing.value
                            ? Icons.graphic_eq_rounded
                            : Icons.pause_rounded,
                        color: ColorConstants.white,
                        size: 22 * scale,
                      ),
                    ),
                ],
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
                        color: titleColor,
                      ),
                    ),
                    SizedBox(height: 2 * scale),
                    Text(
                      [
                        ?track.subtitle,
                        Formatters.duration(track.duration),
                      ].join(' • '),
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
              if (audio.favorites.contains(track.id))
                Icon(
                  Icons.favorite_rounded,
                  size: 16 * scale,
                  color: ColorConstants.tileFavorite,
                ),
              RoundIconButton(
                icon: Icons.more_vert_rounded,
                size: 36,
                onTap: () => showSongMenu(track),
              ),
            ],
          ),
        ),
      );
    });
  }
}

Future<void> showSongMenu(Track track) async {
  final music = Get.find<MusicController>();
  final fav = AudioPlayerService.to.isFavorite(track);
  final action = await showOptionSheet<String>(
    title: track.title,
    options: <SheetOption<String>>[
      const SheetOption(
        value: 'next',
        label: 'Play next',
        icon: Icons.queue_play_next_rounded,
      ),
      const SheetOption(
        value: 'queue',
        label: 'Add to queue',
        icon: Icons.playlist_add_rounded,
      ),
      SheetOption(
        value: 'fav',
        label: fav ? 'Remove from favorites' : 'Add to favorites',
        icon: fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
      ),
      const SheetOption(
        value: 'share',
        label: 'Share',
        icon: Icons.share_rounded,
      ),
      if (track.localSongId != null)
        const SheetOption(
          value: 'delete',
          label: 'Delete from device',
          icon: Icons.delete_outline_rounded,
        ),
    ],
  );
  switch (action) {
    case 'next':
      music.playNext(track);
    case 'queue':
      music.addToQueue(track);
    case 'fav':
      music.toggleFavorite(track);
    case 'share':
      music.share(track);
    case 'delete':
      music.delete(track);
  }
}
