import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/brand_colors.dart';
import '../../../core/theme/color_constants.dart';
import '../../../core/theme/design_metrics.dart';
import '../../../routes/app_pages.dart';
import '../../../widgets/swipe_tab_view.dart';
import '../../../widgets/app_header.dart';
import '../../../widgets/app_search_field.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/round_icon_button.dart';
import '../../../widgets/top_fade.dart';
import '../controllers/youtube_controller.dart';
import 'widgets/home_sections.dart';
import 'widgets/video_card.dart';

/// Home: search/paste bar, shortcuts, recent downloads and a category feed.
/// Typing a query switches to search results; clearing returns to the feed.
class YoutubeView extends GetView<YoutubeController> {
  const YoutubeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        AppHeader(
          title: 'Toomu',
          actions: <Widget>[
            HeaderAction(
              icon: Icons.public_rounded,
              tooltip: 'Browse YouTube',
              onTap: () => Get.toNamed(Routes.browser),
            ),
            HeaderAction(
              icon: Icons.content_paste_rounded,
              tooltip: 'Paste link',
              onTap: controller.pasteFromClipboard,
            ),
          ],
          bottom: AppSearchField(
            hint: 'Search or paste a YouTube link',
            controller: controller.searchText,
            onSubmitted: controller.submit,
            onChanged: (v) {
              if (v.isEmpty) controller.clearResults();
            },
          ),
        ),
        Expanded(
          child: TopFade(
            child: Obx(
              () => controller.searching.value
                  ? const _SearchResults()
                  : const _HomeFeed(),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- home feed

class _HomeFeed extends GetView<YoutubeController> {
  const _HomeFeed();

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;

    int last() => controller.categories.length - 1;
    // Swipe left/right on the feed to move between categories.
    return SwipeToSwitch(
      onNext: () => controller.selectCategory(
        (controller.feedIndex.value + 1).clamp(0, last()),
      ),
      onPrevious: () => controller.selectCategory(
        (controller.feedIndex.value - 1).clamp(0, last()),
      ),
      child: RefreshIndicator(
        color: BrandColors.of(context).primary,
        onRefresh: () => controller.loadFeed(refresh: true),
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.pixels > n.metrics.maxScrollExtent - 800) {
              controller.loadMoreFeed();
            }
            return false;
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: <Widget>[
              const SliverToBoxAdapter(child: QuickAccessRow()),
              const SliverToBoxAdapter(child: SitesRow()),
              const SliverToBoxAdapter(child: RecentDownloadsStrip()),
              const SliverToBoxAdapter(child: RecentSearchesRow()),
              SliverToBoxAdapter(child: SizedBox(height: 8 * scale)),
              SliverPersistentHeader(
                pinned: true,
                delegate: FeedChipsHeader(scale: scale),
              ),
              Obx(() {
                if (controller.feedLoading.value) {
                  return SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      16 * scale,
                      4 * scale,
                      16 * scale,
                      24 * scale,
                    ),
                    sliver: SliverList.separated(
                      itemCount: 3,
                      separatorBuilder: (_, _) => SizedBox(height: 16 * scale),
                      itemBuilder: (_, _) => const VideoSkeleton(),
                    ),
                  );
                }
                if (controller.feedError.value != null &&
                    controller.feed.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.only(top: 24 * scale),
                      child: EmptyState(
                        icon: Icons.wifi_off_rounded,
                        title: "Couldn't load videos",
                        message: controller.feedError.value!,
                        actionLabel: 'Try again',
                        onAction: controller.loadFeed,
                      ),
                    ),
                  );
                }
                final items = controller.feed;
                return SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    16 * scale,
                    4 * scale,
                    16 * scale,
                    24 * scale,
                  ),
                  sliver: SliverList.separated(
                    itemCount:
                        items.length +
                        (controller.feedLoadingMore.value ? 1 : 0),
                    separatorBuilder: (_, _) => SizedBox(height: 16 * scale),
                    itemBuilder: (_, i) {
                      if (i >= items.length) {
                        return Padding(
                          padding: EdgeInsets.all(12 * scale),
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }
                      final video = items[i];
                      return Obx(
                        () => VideoCard(
                          video: video,
                          onTap: () =>
                              controller.openVideo(video.id.value, known: video),
                          onWatch: () => controller.watchFromCard(video),
                          onPressStart: () => controller.prefetch(video),
                          watchLoading: controller.watchingId.value == video.id.value,
                        ),
                      );
                    },
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ search results

class _SearchResults extends GetView<YoutubeController> {
  const _SearchResults();

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final Color ink = ColorConstants.textOn(context.isDark);

    return Column(
      children: <Widget>[
        Padding(
          padding: EdgeInsets.fromLTRB(16 * scale, 12 * scale, 8 * scale, 0),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Obx(
                  () => Text.rich(
                    TextSpan(
                      text: 'Results for ',
                      style: TextStyle(color: ink.withValues(alpha: 0.6)),
                      children: <InlineSpan>[
                        TextSpan(
                          text: '"${controller.searchQuery.value}"',
                          style: TextStyle(
                            color: ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14 * scale,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              RoundIconButton(
                icon: Icons.close_rounded,
                size: 36,
                tooltip: 'Back to home',
                onTap: controller.closeSearch,
              ),
            ],
          ),
        ),
        Expanded(
          child: Obx(() {
            if (controller.loading.value) {
              return ListView.separated(
                padding: EdgeInsets.fromLTRB(
                  16 * scale,
                  12 * scale,
                  16 * scale,
                  24 * scale,
                ),
                itemCount: 3,
                separatorBuilder: (_, _) => SizedBox(height: 16 * scale),
                itemBuilder: (_, _) => const VideoSkeleton(),
              );
            }
            if (controller.error.value != null) {
              return EmptyState(
                icon: Icons.wifi_off_rounded,
                title: 'Something went wrong',
                message: controller.error.value!,
                actionLabel: 'Try again',
                onAction: () => controller.search(controller.searchQuery.value),
              );
            }
            if (controller.results.isEmpty) {
              return const EmptyState(
                icon: Icons.search_off_rounded,
                title: 'No results',
                message: 'Try a different search or paste a link.',
              );
            }
            return NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.pixels > n.metrics.maxScrollExtent - 600) {
                  controller.loadMore();
                }
                return false;
              },
              child: ListView.separated(
                padding: EdgeInsets.fromLTRB(
                  16 * scale,
                  12 * scale,
                  16 * scale,
                  24 * scale,
                ),
                itemCount:
                    controller.results.length +
                    (controller.loadingMore.value ? 1 : 0),
                separatorBuilder: (_, _) => SizedBox(height: 16 * scale),
                itemBuilder: (_, i) {
                  if (i >= controller.results.length) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final video = controller.results[i];
                  return Obx(
                    () => VideoCard(
                      video: video,
                      onTap: () =>
                          controller.openVideo(video.id.value, known: video),
                      onWatch: () => controller.watchFromCard(video),
                      onPressStart: () => controller.prefetch(video),
                      watchLoading: controller.watchingId.value == video.id.value,
                    ),
                  );
                },
              ),
            );
          }),
        ),
      ],
    );
  }
}
