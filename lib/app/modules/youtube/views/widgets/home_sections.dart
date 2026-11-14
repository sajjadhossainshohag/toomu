import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/theme/brand_colors.dart';
import '../../../../core/theme/color_constants.dart';
import '../../../../core/theme/design_metrics.dart';
import '../../../../data/models/download_task.dart';
import '../../../../routes/app_pages.dart';
import '../../../../services/download_service.dart';
import '../../../../services/remote_config_service.dart';
import '../../../../widgets/app_group.dart';
import '../../../../widgets/segmented_tabs.dart';
import '../../../../widgets/track_artwork.dart';
import '../../../downloads/controllers/downloads_controller.dart';
import '../../../home/controllers/home_controller.dart';
import '../../../home/home_tabs.dart';
import '../../controllers/youtube_controller.dart';

/// Three shortcut tiles: Downloads, Music, Paste link.
class QuickAccessRow extends StatelessWidget {
  const QuickAccessRow({super.key});

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final home = Get.find<HomeController>();
    final yt = Get.find<YoutubeController>();
    final service = DownloadService.to;

    return Padding(
      padding: EdgeInsets.fromLTRB(16 * scale, 16 * scale, 16 * scale, 0),
      child: Obx(() {
        final active = service.tasks.where((t) => t.isActive).length;
        final saved = service.completed.length;
        return Row(
          children: <Widget>[
            Expanded(
              child: _QuickTile(
                icon: Icons.download_rounded,
                tint: ColorConstants.tileDownloads,
                label: 'Downloads',
                subtitle: active > 0 ? '$active in progress' : '$saved saved',
                badge: active > 0 ? '$active' : null,
                onTap: () => home.openTab(HomeTabs.downloads),
              ),
            ),
            SizedBox(width: 10 * scale),
            Expanded(
              child: _QuickTile(
                icon: Icons.library_music_rounded,
                tint: ColorConstants.tileAudio,
                label: 'Music',
                subtitle: 'Play offline',
                onTap: () => home.openTab(HomeTabs.music),
              ),
            ),
            SizedBox(width: 10 * scale),
            Expanded(
              child: _QuickTile(
                icon: Icons.content_paste_go_rounded,
                tint: ColorConstants.tileShare,
                label: 'Paste link',
                subtitle: 'From clipboard',
                onTap: yt.pasteFromClipboard,
              ),
            ),
          ],
        );
      }),
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.icon,
    required this.tint,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final Color tint;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final bool dark = context.isDark;
    final Color ink = ColorConstants.textOn(dark);
    return Material(
      color: ColorConstants.groupOn(dark),
      borderRadius: BorderRadius.circular(16 * scale),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16 * scale),
        child: Padding(
          padding: EdgeInsets.all(12 * scale),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  GlyphTile(icon: icon, tint: tint),
                  if (badge != null)
                    Positioned(
                      right: -5 * scale,
                      top: -5 * scale,
                      child: Container(
                        constraints: BoxConstraints(minWidth: 18 * scale),
                        padding: EdgeInsets.symmetric(horizontal: 4 * scale, vertical: 1 * scale),
                        decoration: BoxDecoration(
                          color: ColorConstants.error,
                          borderRadius: BorderRadius.circular(9 * scale),
                          border: Border.all(color: ColorConstants.groupOn(dark).withValues(alpha: 1), width: 1.5 * scale),
                        ),
                        child: Text(
                          badge!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10 * scale,
                            fontWeight: FontWeight.w800,
                            color: ColorConstants.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(height: 10 * scale),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13 * scale, fontWeight: FontWeight.w700, color: ink),
              ),
              SizedBox(height: 1 * scale),
              Text(
                subtitle,
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
      ),
    );
  }
}

/// Snaptube-style site grid: opens each site in the in-app browser, where
/// supported pages get a Download button.
class SitesRow extends StatelessWidget {
  const SitesRow({super.key});

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final Color ink = ColorConstants.textOn(context.isDark);
    final sites = RemoteConfigService.to.sites;

    Widget tile({required IconData icon, required Color color, required String label, required VoidCallback onTap}) =>
        GestureDetector(
          onTap: onTap,
          child: SizedBox(
            width: 68 * scale,
            child: Column(
              children: <Widget>[
                Container(
                  width: 52 * scale,
                  height: 52 * scale,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(18 * scale),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: color.withValues(alpha: 0.35),
                        blurRadius: 12 * scale,
                        offset: Offset(0, 4 * scale),
                      ),
                    ],
                  ),
                  child: Icon(icon, size: 26 * scale, color: ColorConstants.white),
                ),
                SizedBox(height: 6 * scale),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5 * scale, fontWeight: FontWeight.w600, color: ink.withValues(alpha: 0.8)),
                ),
              ],
            ),
          ),
        );

    return Obx(() => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const SectionTitle('Sites'),
            SizedBox(
              height: 80 * scale,
              child: ListView(
                padding: EdgeInsets.symmetric(horizontal: 12 * scale),
                scrollDirection: Axis.horizontal,
                children: <Widget>[
                  for (final s in sites)
                    tile(
                      icon: s.icon,
                      color: s.color,
                      label: s.name,
                      onTap: () => Get.toNamed(Routes.browser, arguments: s.url),
                    ),
                  tile(
                    icon: Icons.public_rounded,
                    color: ColorConstants.tileFolder,
                    label: 'Browser',
                    onTap: () => Get.toNamed(Routes.browser, arguments: 'https://www.google.com/'),
                  ),
                ],
              ),
            ),
          ],
        ));
  }
}

/// Horizontal strip of the latest finished downloads.
class RecentDownloadsStrip extends StatelessWidget {
  const RecentDownloadsStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final service = DownloadService.to;

    return Obx(() {
      final items = service.completed.take(10).toList();
      if (items.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionTitle(
            'Recent downloads',
            trailing: _TextAction(
              label: 'See all',
              onTap: () {
                Get.find<DownloadsController>().tab.value = 1;
                Get.find<HomeController>().openTab(HomeTabs.downloads);
              },
            ),
          ),
          SizedBox(
            height: 132 * scale,
            child: ListView.separated(
              padding: EdgeInsets.symmetric(horizontal: 16 * scale),
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, _) => SizedBox(width: 12 * scale),
              itemBuilder: (_, i) => _RecentCard(task: items[i]),
            ),
          ),
        ],
      );
    });
  }
}

class _RecentCard extends StatelessWidget {
  const _RecentCard({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final Color ink = ColorConstants.textOn(context.isDark);
    final bool audio = task.kind == DownloadKind.audio;
    final IconData icon = audio ? Icons.music_note_rounded : Icons.play_arrow_rounded;

    return GestureDetector(
      onTap: () => Get.find<DownloadsController>().open(task),
      child: SizedBox(
        width: 148 * scale,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(12 * scale),
              child: SizedBox(
                width: 148 * scale,
                height: 83 * scale,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    task.thumbnailUrl.isEmpty
                        ? ArtworkPlaceholder(size: 148, radius: 0, icon: icon)
                        : CachedNetworkImage(
                            imageUrl: task.thumbnailUrl,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) => ArtworkPlaceholder(size: 148, radius: 0, icon: icon),
                          ),
                    Center(
                      child: Container(
                        width: 32 * scale,
                        height: 32 * scale,
                        decoration: BoxDecoration(
                          color: ColorConstants.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(icon, size: 20 * scale, color: ColorConstants.white),
                      ),
                    ),
                    Positioned(
                      right: 6 * scale,
                      bottom: 6 * scale,
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 6 * scale, vertical: 2 * scale),
                        decoration: BoxDecoration(
                          color: ColorConstants.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(6 * scale),
                        ),
                        child: Text(
                          audio ? task.extension.toUpperCase() : task.qualityLabel,
                          style: TextStyle(
                            fontSize: 9.5 * scale,
                            fontWeight: FontWeight.w800,
                            color: ColorConstants.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 6 * scale),
            Text(
              task.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12 * scale,
                height: 1.3,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal chips of recent searches.
class RecentSearchesRow extends StatelessWidget {
  const RecentSearchesRow({super.key});

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final bool dark = context.isDark;
    final Color ink = ColorConstants.textOn(dark);
    final yt = Get.find<YoutubeController>();

    return Obx(() {
      if (yt.history.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionTitle(
            'Recent searches',
            trailing: _TextAction(label: 'Clear', onTap: yt.clearHistory),
          ),
          SizedBox(
            height: 34 * scale,
            child: ListView.separated(
              padding: EdgeInsets.symmetric(horizontal: 16 * scale),
              scrollDirection: Axis.horizontal,
              itemCount: yt.history.length,
              separatorBuilder: (_, _) => SizedBox(width: 8 * scale),
              itemBuilder: (_, i) {
                final q = yt.history[i];
                return GestureDetector(
                  onTap: () => yt.useHistory(q),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 12 * scale),
                    decoration: BoxDecoration(
                      color: ColorConstants.groupOn(dark),
                      borderRadius: BorderRadius.circular(12 * scale),
                      border: Border.all(color: ink.withValues(alpha: 0.06)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.history_rounded, size: 15 * scale, color: ink.withValues(alpha: 0.5)),
                        SizedBox(width: 6 * scale),
                        Text(
                          q,
                          style: TextStyle(
                            fontSize: 12.5 * scale,
                            fontWeight: FontWeight.w600,
                            color: ink.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );
    });
  }
}

/// Pinned category chip bar for the feed.
class FeedChipsHeader extends SliverPersistentHeaderDelegate {
  FeedChipsHeader({required this.scale});

  final double scale;

  @override
  double get minExtent => 56 * scale;

  @override
  double get maxExtent => 56 * scale;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final yt = Get.find<YoutubeController>();
    return ColoredBox(
      color: ColorConstants.pageOn(context.isDark),
      child: Center(
        child: Obx(
          () => SegmentedTabs(
            labels: yt.categories.map((c) => c.label).toList(),
            selected: yt.feedIndex.value,
            onSelect: yt.selectCategory,
            scrollable: true,
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(FeedChipsHeader old) => old.scale != scale;
}

/// Placeholder card while the feed loads.
class VideoSkeleton extends StatelessWidget {
  const VideoSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final bool dark = context.isDark;
    final Color bone = ColorConstants.textOn(dark).withValues(alpha: dark ? 0.07 : 0.06);
    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(color: bone, borderRadius: BorderRadius.circular(6 * scale)),
        );
    return Container(
      decoration: BoxDecoration(
        color: ColorConstants.groupOn(dark),
        borderRadius: BorderRadius.circular(16 * scale),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AspectRatio(aspectRatio: 16 / 9, child: ColoredBox(color: bone)),
          Padding(
            padding: EdgeInsets.all(14 * scale),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                bar(240 * scale, 12 * scale),
                SizedBox(height: 8 * scale),
                bar(160 * scale, 12 * scale),
                SizedBox(height: 10 * scale),
                bar(90 * scale, 10 * scale),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TextAction extends StatelessWidget {
  const _TextAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13 * context.scale,
            fontWeight: FontWeight.w600,
            color: context.isDark
                ? BrandColors.of(context).accent
                : BrandColors.of(context).primary,
          ),
        ),
      );
}
