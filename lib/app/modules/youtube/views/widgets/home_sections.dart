import 'dart:math';

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:get/get.dart';

import '../../../../core/theme/brand_colors.dart';
import '../../../../core/theme/color_constants.dart';
import '../../../../core/theme/design_metrics.dart';
import '../../../../routes/app_pages.dart';
import '../../../../services/download_service.dart';
import '../../../../services/remote_config_service.dart';
import '../../../../widgets/segmented_tabs.dart';
import '../../../downloads/controllers/downloads_controller.dart';
import '../../../home/controllers/home_controller.dart';
import '../../../home/home_tabs.dart';
import '../../controllers/youtube_controller.dart';
import 'video_row.dart';

/// Round site shortcuts; each opens in the in-app browser.
class SiteIconsRow extends StatelessWidget {
  const SiteIconsRow({super.key});

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final Color ink = ColorConstants.textOn(context.isDark);
    return Obx(
      () => SizedBox(
        height: 84 * scale,
        child: ListView(
          padding: EdgeInsets.fromLTRB(8 * scale, 14 * scale, 8 * scale, 0),
          scrollDirection: Axis.horizontal,
          children: <Widget>[
            for (final s in RemoteConfigService.to.sites)
              InkResponse(
                onTap: () => Uri.tryParse(s.url)?.host.contains('youtube.') ?? false
                    ? Get.find<HomeController>().openTab(HomeTabs.youtube)
                    : Get.toNamed(Routes.browser, arguments: s.url),
                radius: 34 * scale,
                child: SizedBox(
                  width: 72 * scale,
                  child: Column(
                    children: <Widget>[
                      Container(
                        width: 46 * scale,
                        height: 46 * scale,
                        decoration: BoxDecoration(color: s.color, shape: BoxShape.circle),
                        child: Icon(s.icon, size: 22 * scale, color: ColorConstants.white),
                      ),
                      SizedBox(height: 5 * scale),
                      Text(
                        s.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5 * scale, fontWeight: FontWeight.w600, color: ink.withValues(alpha: 0.8)),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Slim progress bar, only while something downloads.
class ActiveDownloadsBar extends StatelessWidget {
  const ActiveDownloadsBar({super.key});

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final bool dark = context.isDark;
    final Color ink = ColorConstants.textOn(dark);
    final BrandColors brand = BrandColors.of(context);
    final BorderRadius radius = BorderRadius.circular(16 * scale);
    return Obx(() {
      final running = DownloadService.to.tasks.where((t) => t.isActive).toList();
      if (running.isEmpty) return const SizedBox.shrink();
      final total = running.fold<int>(0, (s, t) => s + t.totalBytes.value);
      final got = running.fold<int>(0, (s, t) => s + t.receivedBytes.value);
      final double? progress = total > 0 ? (got / total).clamp(0.0, 1.0) : null;
      return Padding(
        padding: EdgeInsets.fromLTRB(16 * scale, 12 * scale, 16 * scale, 0),
        child: Material(
          color: ColorConstants.groupOn(dark),
          borderRadius: radius,
          child: InkWell(
            borderRadius: radius,
            onTap: () {
              Get.find<DownloadsController>().tab.value = 0;
              Get.find<HomeController>().openTab(HomeTabs.downloads);
            },
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 10 * scale),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 30 * scale,
                    height: 30 * scale,
                    decoration: BoxDecoration(gradient: brand.pillGradient, shape: BoxShape.circle),
                    child: Icon(Icons.download_rounded, size: 16 * scale, color: ColorConstants.white),
                  ),
                  SizedBox(width: 12 * scale),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          [
                            '${running.length} downloading',
                            if (progress != null) '${(progress * 100).round()}%',
                          ].join(' · '),
                          style: TextStyle(fontSize: 13 * scale, fontWeight: FontWeight.w700, color: ink),
                        ),
                        SizedBox(height: 6 * scale),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2 * scale),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 4 * scale,
                            backgroundColor: ink.withValues(alpha: 0.08),
                            color: brand.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 12 * scale),
                  _TextAction(label: 'View', onTap: () => Get.find<HomeController>().openTab(HomeTabs.downloads)),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}

/// Shown under the search box while it is focused and empty.
class RecentSearchesList extends StatelessWidget {
  const RecentSearchesList({super.key});

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final bool dark = context.isDark;
    final Color ink = ColorConstants.textOn(dark);
    final yt = Get.find<YoutubeController>();
    // Part of the search field: a tap here would otherwise unfocus it first, and the list would be gone before
    // the tap lands.
    return TextFieldTapRegion(
      child: Obx(
        () => ListView(
          padding: EdgeInsets.fromLTRB(16 * scale, 10 * scale, 16 * scale, 24 * scale),
          children: <Widget>[
            Container(
              padding: EdgeInsets.symmetric(vertical: 6 * scale),
              decoration: BoxDecoration(color: ColorConstants.groupOn(dark), borderRadius: BorderRadius.circular(18 * scale)),
              child: Column(
                children: <Widget>[
                  Padding(
                    padding: EdgeInsets.fromLTRB(16 * scale, 8 * scale, 16 * scale, 4 * scale),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            'Recent searches',
                            style: TextStyle(fontSize: 13 * scale, fontWeight: FontWeight.w700, color: ink.withValues(alpha: 0.6)),
                          ),
                        ),
                        _TextAction(label: 'Clear', onTap: yt.clearHistory),
                      ],
                    ),
                  ),
                  for (final q in yt.history) _QueryRow(query: q, icon: Iconsax.clock_copy),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown under the search box while typing, like YouTube's: matching recent searches, YouTube's suggested
/// searches, then a few videos for what was typed.
class SearchSuggestionsList extends StatelessWidget {
  const SearchSuggestionsList({required this.typed, super.key});

  final String typed;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final bool dark = context.isDark;
    final Color ink = ColorConstants.textOn(dark);
    final yt = Get.find<YoutubeController>();
    return TextFieldTapRegion(
      child: Obx(() {
        final q = typed.trim().toLowerCase();
        final recent = yt.history.where((h) => h.toLowerCase().contains(q)).take(3).toList();
        final seen = {for (final r in recent) r.toLowerCase()};
        final suggested = yt.suggestions.where((s) => seen.add(s.toLowerCase())).take(8).toList();
        final videos = yt.suggestedVideos.toList();
        return ListView(
          padding: EdgeInsets.fromLTRB(16 * scale, 10 * scale, 16 * scale, 24 * scale),
          children: <Widget>[
            if (recent.isNotEmpty || suggested.isNotEmpty)
              Container(
                padding: EdgeInsets.symmetric(vertical: 6 * scale),
                decoration: BoxDecoration(color: ColorConstants.groupOn(dark), borderRadius: BorderRadius.circular(18 * scale)),
                child: Column(
                  children: <Widget>[
                    for (final r in recent) _QueryRow(query: r, icon: Iconsax.clock_copy, typed: typed),
                    for (final s in suggested) _QueryRow(query: s, icon: Iconsax.search_normal_1_copy, typed: typed),
                  ],
                ),
              ),
            if (videos.isNotEmpty) ...<Widget>[
              Padding(
                padding: EdgeInsets.fromLTRB(4 * scale, 18 * scale, 4 * scale, 4 * scale),
                child: Text(
                  'Videos',
                  style: TextStyle(fontSize: 13 * scale, fontWeight: FontWeight.w700, color: ink.withValues(alpha: 0.6)),
                ),
              ),
              for (final v in videos)
                VideoRow(
                  video: v,
                  onTap: () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    yt.watchFromCard(v);
                  },
                ),
            ],
          ],
        );
      }),
    );
  }
}

/// A search to run: tap searches it, ↖ puts it in the box to keep typing. The part not typed yet is bold.
class _QueryRow extends StatelessWidget {
  const _QueryRow({required this.query, required this.icon, this.typed = ''});

  final String query;
  final IconData icon;
  final String typed;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final Color ink = ColorConstants.textOn(context.isDark);
    final yt = Get.find<YoutubeController>();
    final style = TextStyle(fontSize: 15 * scale, color: ink);
    final t = typed.trimLeft();
    final completes = t.isNotEmpty && query.toLowerCase().startsWith(t.toLowerCase());
    return InkWell(
      onTap: () {
        FocusManager.instance.primaryFocus?.unfocus();
        yt.useHistory(query);
      },
      child: Padding(
        padding: EdgeInsets.only(left: 16 * scale, right: 4 * scale),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 20 * scale, color: ink.withValues(alpha: 0.55)),
            SizedBox(width: 14 * scale),
            Expanded(
              child: Text.rich(
                completes
                    ? TextSpan(
                        children: <TextSpan>[
                          TextSpan(text: query.substring(0, t.length)),
                          TextSpan(text: query.substring(t.length), style: const TextStyle(fontWeight: FontWeight.w700)),
                        ],
                      )
                    : TextSpan(text: query),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
            IconButton(
              tooltip: 'Edit "$query"',
              onPressed: () => yt.fillSearch(query),
              // Iconsax has no up-left arrow: its up arrow, turned.
              icon: Transform.rotate(
                angle: -pi / 4,
                child: Icon(Iconsax.arrow_up_3_copy, size: 18 * scale, color: ink.withValues(alpha: 0.45)),
              ),
            ),
          ],
        ),
      ),
    );
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
