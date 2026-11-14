import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/color_constants.dart';
import '../../../core/theme/design_metrics.dart';
import '../../../data/models/track.dart';
import '../../../widgets/app_header.dart';
import '../../../widgets/app_search_field.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/gradient_pill.dart';
import '../../../widgets/option_sheet.dart';
import '../../../widgets/outline_pill.dart';
import '../../../widgets/segmented_tabs.dart';
import '../../../widgets/swipe_tab_view.dart';
import '../../../widgets/top_fade.dart';
import '../controllers/music_controller.dart';
import 'widgets/collection_tile.dart';
import 'widgets/song_tile.dart';

class MusicView extends GetView<MusicController> {
  const MusicView({super.key});

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;

    return Column(
      children: <Widget>[
        Obx(
          () => AppHeader(
            title: 'Music',
            subtitle: '${controller.totalSongs} songs on this device',
            actions: <Widget>[
              HeaderAction(
                icon: Icons.sort_rounded,
                tooltip: 'Sort',
                onTap: _pickSort,
              ),
              HeaderAction(
                icon: Icons.refresh_rounded,
                tooltip: 'Rescan',
                onTap: controller.load,
              ),
            ],
            bottom: AppSearchField(
              hint: 'Search songs and albums',
              onChanged: (v) => controller.query.value = v,
            ),
          ),
        ),
        SizedBox(height: 6 * scale),
        Obx(
          () => SegmentedTabs(
            labels: MusicController.tabs,
            selected: controller.tab.value,
            onSelect: (i) => controller.tab.value = i,
            scrollable: true,
          ),
        ),
        SizedBox(height: 4 * scale),
        Expanded(
          child: Obx(() {
            if (controller.loading.value) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!controller.hasPermission.value) {
              return EmptyState(
                icon: Icons.lock_open_rounded,
                title: 'Allow music access',
                message:
                    'Toomu needs permission to find the songs on your device.',
                actionLabel: 'Grant access',
                onAction: controller.load,
              );
            }
            return TopFade(
              child: SwipeTabView(
                index: controller.tab,
                count: MusicController.tabs.length,
                itemBuilder: (_, i) => Obx(() => _body(i)),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _body(int tab) {
    switch (tab) {
      case 0:
        return _SongList(tracks: controller.songs);
      case 1:
        return _AlbumGrid(items: controller.albums);
      case 2:
        return _CollectionList(
          items: controller.folders,
          icon: Icons.folder_rounded,
          tint: ColorConstants.tileFolder,
        );
      default:
        return _SongList(tracks: controller.favorites, favorites: true);
    }
  }

  Future<void> _pickSort() async {
    final picked = await showOptionSheet<SongSort>(
      title: 'Sort songs by',
      selected: controller.sort.value,
      options: const <SheetOption<SongSort>>[
        SheetOption(
          value: SongSort.title,
          label: 'Title',
          icon: Icons.sort_by_alpha_rounded,
        ),
        SheetOption(
          value: SongSort.recent,
          label: 'Recently added',
          icon: Icons.schedule_rounded,
        ),
        SheetOption(
          value: SongSort.duration,
          label: 'Duration',
          icon: Icons.timer_outlined,
        ),
      ],
    );
    if (picked != null) controller.sort.value = picked;
  }
}

class _SongList extends GetView<MusicController> {
  const _SongList({required this.tracks, this.favorites = false});

  final List<Track> tracks;
  final bool favorites;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    if (tracks.isEmpty) {
      return EmptyState(
        icon: favorites ? Icons.favorite_rounded : Icons.library_music_rounded,
        title: favorites ? 'No favorites yet' : 'No songs found',
        message: favorites
            ? 'Tap the heart in the player to save songs here.'
            : 'Downloaded audio and music on your device will show up here.',
      );
    }
    return ListView.builder(
      padding: EdgeInsets.only(top: 12 * scale, bottom: 24 * scale),
      itemCount: tracks.length + 1,
      itemBuilder: (_, i) {
        if (i == 0) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
              16 * scale,
              4 * scale,
              16 * scale,
              10 * scale,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: GradientPill(
                    label: 'Shuffle',
                    icon: Icons.shuffle_rounded,
                    height: 44,
                    onTap: () => controller.shuffleAll(tracks),
                  ),
                ),
                SizedBox(width: 12 * scale),
                Expanded(
                  child: OutlinePill(
                    label: 'Play all',
                    icon: Icons.play_arrow_rounded,
                    height: 44,
                    onTap: () => controller.playAll(tracks),
                  ),
                ),
              ],
            ),
          );
        }
        final t = tracks[i - 1];
        return SongTile(track: t, onTap: () => controller.play(tracks, t));
      },
    );
  }
}

class _AlbumGrid extends GetView<MusicController> {
  const _AlbumGrid({required this.items});

  final List<MusicCollection> items;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    if (items.isEmpty) {
      return const EmptyState(
        icon: Icons.album_rounded,
        title: 'No albums',
        message: 'Nothing to show yet.',
      );
    }
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(
        16 * scale,
        16 * scale,
        16 * scale,
        24 * scale,
      ),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12 * scale,
        crossAxisSpacing: 12 * scale,
        childAspectRatio: 0.78,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => AlbumCard(
        collection: items[i],
        onTap: () => controller.openCollection(items[i]),
      ),
    );
  }
}

class _CollectionList extends GetView<MusicController> {
  const _CollectionList({
    required this.items,
    required this.icon,
    required this.tint,
  });

  final List<MusicCollection> items;
  final IconData icon;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return EmptyState(
        icon: icon,
        title: 'Nothing here',
        message: 'No music found.',
      );
    }
    return ListView.builder(
      padding: EdgeInsets.only(
        top: 12 * context.scale,
        bottom: 24 * context.scale,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) => CollectionRow(
        collection: items[i],
        icon: icon,
        tint: tint,
        onTap: () => controller.openCollection(items[i]),
      ),
    );
  }
}
