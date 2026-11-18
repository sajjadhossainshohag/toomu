import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../../data/providers/youtube/feed_mix.dart';

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

/// Home: search/paste bar, site shortcuts, download progress and a category feed.
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
            HeaderAction(icon: Icons.video_library_outlined, tooltip: 'Library', onTap: () => Get.toNamed(Routes.library)),
            HeaderAction(icon: Iconsax.global_copy, tooltip: 'Browser', onTap: () => Get.toNamed(Routes.browser)),
          ],
          bottom: AppSearchField(
            hint: 'Search or paste a YouTube link',
            controller: controller.searchText,
            onSubmitted: controller.submit,
            onChanged: (v) {
              if (v.isEmpty) controller.clearResults();
            },
            onFocusChange: (f) => controller.searchFocused.value = f,
            trailing: IconButton(
              tooltip: 'Paste link',
              onPressed: controller.pasteFromClipboard,
              icon: Icon(Iconsax.clipboard_import_copy, color: BrandColors.of(context).primary),
            ),
          ),
        ),
        Expanded(
          child: TopFade(
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: Obx(() => controller.searching.value ? const _SearchResults() : const _HomeFeed()),
                ),
                // Over the feed, not instead of it: the feed keeps its scroll position. Positioned even when
                // empty: an unpositioned child would size the Stack to nothing.
                Positioned.fill(
                  child: Obx(
                    () => controller.searchFocused.value && controller.history.isNotEmpty
                        ? ValueListenableBuilder<TextEditingValue>(
                            valueListenable: controller.searchText,
                            builder: (context, text, _) => text.text.isEmpty
                                ? ColoredBox(
                                    color: ColorConstants.pageOn(context.isDark),
                                    child: const RecentSearchesList(),
                                  )
                                : const SizedBox.shrink(),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
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
      onNext: () => controller.selectCategory((controller.feedIndex.value + 1).clamp(0, last())),
      onPrevious: () => controller.selectCategory((controller.feedIndex.value - 1).clamp(0, last())),
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
              const SliverToBoxAdapter(child: SiteIconsRow()),
              const SliverToBoxAdapter(child: ActiveDownloadsBar()),
              SliverToBoxAdapter(child: SizedBox(height: 8 * scale)),
              SliverPersistentHeader(pinned: true, delegate: FeedChipsHeader(scale: scale)),
              // Signed in but shown the general feed: why, and a way back.
              Obx(() {
                final notice = controller.feedNotice.value;
                if (notice == null || controller.feedIndex.value != 0) {
                  return const SliverToBoxAdapter(child: SizedBox.shrink());
                }
                return SliverToBoxAdapter(
                  child: FeedNoticeCard(notice: notice, onAction: controller.onFeedNotice),
                );
              }),
              Obx(() {
                if (controller.feedLoading.value) {
                  return SliverPadding(
                    padding: EdgeInsets.fromLTRB(16 * scale, 4 * scale, 16 * scale, 24 * scale),
                    sliver: SliverList.separated(
                      itemCount: 3,
                      separatorBuilder: (_, _) => SizedBox(height: 16 * scale),
                      itemBuilder: (_, _) => const VideoSkeleton(),
                    ),
                  );
                }
                if (controller.feedError.value != null && controller.feed.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.only(top: 24 * scale),
                      child: EmptyState(
                        icon: Iconsax.cloud_cross_copy,
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
                  padding: EdgeInsets.fromLTRB(16 * scale, 4 * scale, 16 * scale, 24 * scale),
                  sliver: SliverList.separated(
                    itemCount: items.length + (controller.feedLoadingMore.value ? 1 : 0),
                    separatorBuilder: (_, _) => SizedBox(height: 16 * scale),
                    itemBuilder: (_, i) {
                      if (i >= items.length) {
                        return Padding(
                          padding: EdgeInsets.all(12 * scale),
                          child: const Center(child: CircularProgressIndicator()),
                        );
                      }
                      final video = items[i];
                      return Obx(
                        () => VideoCard(
                          video: video,
                          onTap: () => controller.watchFromCard(video),
                          onMore: () => controller.showVideoMenu(video),
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
                          style: TextStyle(color: ink, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14 * scale, fontWeight: FontWeight.w500),
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
                padding: EdgeInsets.fromLTRB(16 * scale, 12 * scale, 16 * scale, 24 * scale),
                itemCount: 3,
                separatorBuilder: (_, _) => SizedBox(height: 16 * scale),
                itemBuilder: (_, _) => const VideoSkeleton(),
              );
            }
            if (controller.error.value != null) {
              return EmptyState(
                icon: Iconsax.cloud_cross_copy,
                title: 'Something went wrong',
                message: controller.error.value!,
                actionLabel: 'Try again',
                onAction: () => controller.search(controller.searchQuery.value),
              );
            }
            if (controller.results.isEmpty) {
              return const EmptyState(
                icon: Iconsax.search_zoom_out_copy,
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
                padding: EdgeInsets.fromLTRB(16 * scale, 12 * scale, 16 * scale, 24 * scale),
                itemCount: controller.results.length + (controller.loadingMore.value ? 1 : 0),
                separatorBuilder: (_, _) => SizedBox(height: 16 * scale),
                itemBuilder: (_, i) {
                  if (i >= controller.results.length) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final video = controller.results[i];
                  return Obx(
                    () => VideoCard(
                      video: video,
                      onTap: () => controller.watchFromCard(video),
                      onMore: () => controller.showVideoMenu(video),
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

/// "Your YouTube sign-in expired. Showing popular videos.  [Sign in]"
class FeedNoticeCard extends StatelessWidget {
  const FeedNoticeCard({required this.notice, required this.onAction, super.key});

  final HomeFeedNotice notice;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final bool dark = context.isDark;
    final Color ink = ColorConstants.textOn(dark);
    final Color primary = BrandColors.of(context).primary;
    final signIn = notice.action == HomeFeedAction.signIn;
    return Padding(
      padding: EdgeInsets.fromLTRB(16 * scale, 4 * scale, 16 * scale, 8 * scale),
      child: Container(
        padding: EdgeInsets.fromLTRB(14 * scale, 10 * scale, 6 * scale, 10 * scale),
        decoration: BoxDecoration(
          color: primary.withValues(alpha: dark ? 0.16 : 0.08),
          borderRadius: BorderRadius.circular(14 * scale),
        ),
        child: Row(
          children: <Widget>[
            Icon(signIn ? Iconsax.lock_copy : Iconsax.info_circle_copy, size: 20 * scale, color: primary),
            SizedBox(width: 10 * scale),
            Expanded(
              child: Text(
                notice.message,
                style: TextStyle(fontSize: 13 * scale, height: 1.3, fontWeight: FontWeight.w500, color: ink),
              ),
            ),
            TextButton(
              onPressed: onAction,
              child: Text(
                signIn ? 'Sign in' : 'Retry',
                style: TextStyle(fontSize: 13.5 * scale, fontWeight: FontWeight.w700, color: primary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
