import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/color_constants.dart';
import '../../../core/theme/design_metrics.dart';
import '../../../widgets/gradient_pill.dart';
import '../../../widgets/mini_player.dart';
import '../../../widgets/outline_pill.dart';
import '../../../widgets/track_artwork.dart';
import '../../../widgets/app_header.dart';
import '../controllers/collection_controller.dart';
import 'widgets/song_tile.dart';

class CollectionView extends GetView<CollectionController> {
  const CollectionView({super.key});

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final c = controller.collection;
    final Color ink = ColorConstants.textOn(context.isDark);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            PageBackHeader(title: c.title),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.only(bottom: 24 * scale),
                itemCount: c.tracks.length + 1,
                itemBuilder: (_, i) {
                  if (i == 0) {
                    return Padding(
                      padding: EdgeInsets.fromLTRB(
                        16 * scale,
                        8 * scale,
                        16 * scale,
                        12 * scale,
                      ),
                      child: Column(
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              TrackArtwork(
                                track: c.tracks.first,
                                size: 96,
                                radius: 20,
                                highRes: true,
                              ),
                              SizedBox(width: 16 * scale),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      c.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 18 * scale,
                                        fontWeight: FontWeight.w700,
                                        color: ink,
                                      ),
                                    ),
                                    SizedBox(height: 4 * scale),
                                    Text(
                                      c.subtitle,
                                      maxLines: 2,
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
                            ],
                          ),
                          SizedBox(height: 16 * scale),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: GradientPill(
                                  label: 'Shuffle',
                                  icon: Icons.shuffle_rounded,
                                  height: 44,
                                  onTap: () =>
                                      controller.music.shuffleAll(c.tracks),
                                ),
                              ),
                              SizedBox(width: 12 * scale),
                              Expanded(
                                child: OutlinePill(
                                  label: 'Play all',
                                  icon: Icons.play_arrow_rounded,
                                  height: 44,
                                  onTap: () =>
                                      controller.music.playAll(c.tracks),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }
                  final t = c.tracks[i - 1];
                  return SongTile(
                    track: t,
                    onTap: () => controller.music.play(c.tracks, t),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: const SafeArea(top: false, child: MiniPlayer()),
    );
  }
}
