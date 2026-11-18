import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../../core/theme/brand_colors.dart';
import '../../../core/theme/color_constants.dart';
import '../../../core/theme/design_metrics.dart';
import '../../../data/repositories/video_resume_repository.dart';
import '../../../routes/app_pages.dart';
import '../../../services/download_service.dart';
import '../../../widgets/app_group.dart';
import '../../../widgets/app_header.dart';
import '../../../widgets/app_search_field.dart';
import '../../../widgets/top_fade.dart';
import '../../../widgets/track_artwork.dart';
import '../../browser/address.dart';
import '../../youtube/controllers/youtube_controller.dart';
import '../../youtube/views/widgets/home_sections.dart';
import '../controllers/home_controller.dart';

class HomeHubView extends GetView<HomeController> {
  const HomeHubView({super.key});

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    return Column(
      children: <Widget>[
        AppHeader(
          title: 'Toomu',
          actions: <Widget>[
            HeaderAction(
              icon: Iconsax.global_copy,
              tooltip: 'Browser',
              onTap: () => Get.toNamed(Routes.browser, arguments: newTabUrl),
            ),
            HeaderAction(icon: Iconsax.setting_2_copy, tooltip: 'Settings', onTap: controller.openSettings),
          ],
          bottom: AppSearchField(
            hint: 'Search or paste any link',
            controller: controller.hubSearch,
            onSubmitted: controller.openFromHome,
            trailing: IconButton(
              tooltip: 'Paste link',
              onPressed: controller.pasteFromHome,
              icon: Icon(Iconsax.clipboard_import_copy, color: BrandColors.of(context).primary),
            ),
          ),
        ),
        Expanded(
          child: TopFade(
            child: ListView(
              padding: EdgeInsets.only(bottom: 24 * scale),
              children: const <Widget>[SiteIconsRow(), ActiveDownloadsBar(), _ContinueWatching(), _ShareTip()],
            ),
          ),
        ),
      ],
    );
  }
}

List<(Video, double)> _started() {
  final resume = VideoResumeRepository.instance;
  resume.changed.value;
  return [
    for (final v in Get.find<YoutubeController>().watched)
      if (resume.progressOf('yt:${v.id.value}', v.duration) case final p? when p > 0) (v, p),
  ].take(10).toList();
}

class _ContinueWatching extends StatelessWidget {
  const _ContinueWatching();

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final Color ink = ColorConstants.textOn(context.isDark);
    return Obx(() {
      final started = _started();
      if (started.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionTitle('Continue watching'),
          SizedBox(
            height: 140 * scale,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: DesignMetrics.gutter * scale),
              itemCount: started.length,
              separatorBuilder: (_, _) => SizedBox(width: 10 * scale),
              itemBuilder: (_, i) {
                final (video, progress) = started[i];
                return SizedBox(
                  width: 160 * scale,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12 * scale),
                    onTap: () => Get.find<YoutubeController>().watchFromCard(video),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12 * scale),
                          child: SizedBox(
                            width: 160 * scale,
                            height: 90 * scale,
                            child: Stack(
                              fit: StackFit.expand,
                              children: <Widget>[
                                CachedNetworkImage(
                                  imageUrl: video.thumbnails.mediumResUrl,
                                  fit: BoxFit.cover,
                                  memCacheWidth: (160 * scale * MediaQuery.devicePixelRatioOf(context)).round(),
                                  placeholder: (_, _) => const ArtworkPlaceholder(size: 160, radius: 0, icon: Icons.smart_display_rounded),
                                  errorWidget: (_, _, _) =>
                                      const ArtworkPlaceholder(size: 160, radius: 0, icon: Icons.smart_display_rounded),
                                ),
                                Align(
                                  alignment: Alignment.bottomCenter,
                                  child: LinearProgressIndicator(
                                    value: progress,
                                    minHeight: 3 * scale,
                                    color: ColorConstants.premium,
                                    backgroundColor: ColorConstants.white.withValues(alpha: 0.3),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(height: 6 * scale),
                        Text(
                          video.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12 * scale, height: 1.3, fontWeight: FontWeight.w700, color: ink),
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

class _ShareTip extends StatelessWidget {
  const _ShareTip();

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final Color ink = ColorConstants.textOn(context.isDark);
    return Obx(() {
      if (_started().isNotEmpty || DownloadService.to.tasks.any((t) => t.isActive)) return const SizedBox.shrink();
      return Padding(
        padding: EdgeInsets.fromLTRB(DesignMetrics.gutter * scale, 20 * scale, DesignMetrics.gutter * scale, 0),
        child: Row(
          children: <Widget>[
            Icon(Iconsax.export_1_copy, size: 22 * scale, color: BrandColors.of(context).primary),
            SizedBox(width: 12 * scale),
            Expanded(
              child: Text(
                'To download from YouTube, TikTok or any app, tap Share there and pick Toomu.',
                style: TextStyle(fontSize: 13 * scale, height: 1.4, color: ink.withValues(alpha: 0.7)),
              ),
            ),
          ],
        ),
      );
    });
  }
}
