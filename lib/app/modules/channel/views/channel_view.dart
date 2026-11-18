import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../../core/theme/brand_colors.dart';
import '../../../core/theme/color_constants.dart';
import '../../../core/theme/design_metrics.dart';
import '../../../core/utils/formatters.dart';
import '../../../widgets/segmented_tabs.dart';
import '../../../widgets/track_artwork.dart';
import '../../youtube/controllers/youtube_controller.dart';
import '../../youtube/views/widgets/video_row.dart';
import '../controllers/channel_controller.dart';

/// A YouTube channel: its videos (latest, popular or oldest first) and its Shorts.
class ChannelView extends GetView<ChannelController> {
  const ChannelView({super.key});

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final bool dark = context.isDark;
    final Color ink = ColorConstants.textOn(dark);
    final yt = Get.find<YoutubeController>();

    return Scaffold(
      backgroundColor: ColorConstants.pageOn(dark),
      body: SafeArea(
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.pixels > n.metrics.maxScrollExtent - 600) controller.loadMore();
            return false;
          },
          child: Obx(() {
            final channel = controller.channel.value;
            final name = channel?.title ?? controller.args.title;
            final shorts = controller.shorts.value;
            return CustomScrollView(
              slivers: <Widget>[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(4 * scale, 4 * scale, 16 * scale, 0),
                    child: Row(
                      children: <Widget>[
                        IconButton(
                          tooltip: 'Back',
                          onPressed: Get.back,
                          icon: Icon(Icons.arrow_back_rounded, color: ink),
                        ),
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 17 * scale, fontWeight: FontWeight.w700, color: ink),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16 * scale, 12 * scale, 16 * scale, 16 * scale),
                    child: Row(
                      children: <Widget>[
                        ClipOval(
                          child: SizedBox.square(
                            dimension: 64 * scale,
                            child: channel == null || channel.logoUrl.isEmpty
                                ? _Initial(name: name)
                                : CachedNetworkImage(
                                    imageUrl: channel.logoUrl,
                                    fit: BoxFit.cover,
                                    memCacheWidth: (64 * scale * MediaQuery.devicePixelRatioOf(context)).round(),
                                    errorWidget: (_, _, _) => _Initial(name: name),
                                  ),
                          ),
                        ),
                        SizedBox(width: 14 * scale),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 20 * scale,
                                  height: 1.2,
                                  fontWeight: FontWeight.w800,
                                  color: ink,
                                ),
                              ),
                              if (channel?.subscribersCount != null)
                                Text(
                                  '${Formatters.compact(channel!.subscribersCount!)} subscribers',
                                  style: TextStyle(fontSize: 13 * scale, color: ink.withValues(alpha: 0.6)),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16 * scale),
                    child: SegmentedTabs(
                      labels: const <String>['Videos', 'Shorts'],
                      selected: shorts ? 1 : 0,
                      onSelect: (i) => controller.showShorts(i == 1),
                    ),
                  ),
                ),
                if (!shorts)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16 * scale, 12 * scale, 16 * scale, 4 * scale),
                      child: Wrap(
                        spacing: 8 * scale,
                        children: <Widget>[
                          for (final (sort, label) in const [
                            (VideoSorting.newest, 'Latest'),
                            (VideoSorting.popularity, 'Popular'),
                            (VideoSorting.oldest, 'Oldest'),
                          ])
                            ChoiceChip(
                              label: Text(label),
                              selected: controller.sort.value == sort,
                              onSelected: (_) => controller.sortBy(sort),
                            ),
                        ],
                      ),
                    ),
                  ),
                if (controller.loading.value)
                  const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
                else if (controller.error.value != null || controller.videos.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            controller.error.value ?? (shorts ? 'No Shorts yet.' : 'No videos yet.'),
                            textAlign: TextAlign.center,
                            style: TextStyle(color: ink.withValues(alpha: 0.7)),
                          ),
                          if (controller.error.value != null)
                            TextButton(onPressed: controller.load, child: const Text('Try again')),
                        ],
                      ),
                    ),
                  )
                else if (shorts)
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(16 * scale, 12 * scale, 16 * scale, 16 * scale),
                    sliver: SliverGrid.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 8 * scale,
                        crossAxisSpacing: 8 * scale,
                        childAspectRatio: 9 / 16,
                      ),
                      itemCount: controller.videos.length,
                      itemBuilder: (_, i) => _ShortTile(
                        video: controller.videos[i],
                        onTap: () => yt.openShorts(controller.videos.toList(), i),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.only(top: 8 * scale, bottom: 16 * scale),
                    sliver: SliverList.builder(
                      itemCount: controller.videos.length,
                      itemBuilder: (_, i) {
                        final v = controller.videos[i];
                        return VideoRow(
                          video: v,
                          loading: yt.watchingId.value == v.id.value,
                          onTap: () => yt.watchFromCard(v),
                        );
                      },
                    ),
                  ),
                if (controller.loadingMore.value)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(16 * scale),
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                  ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

class _ShortTile extends StatelessWidget {
  const _ShortTile({required this.video, required this.onTap});

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

class _Initial extends StatelessWidget {
  const _Initial({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final brand = BrandColors.of(context);
    final letter = name.replaceFirst('@', '').trim();
    return ColoredBox(
      color: brand.primary.withValues(alpha: 0.18),
      child: Center(
        child: Text(
          letter.isEmpty ? '?' : letter.characters.first.toUpperCase(),
          style: TextStyle(fontSize: 26 * context.scale, fontWeight: FontWeight.w800, color: brand.primary),
        ),
      ),
    );
  }
}
