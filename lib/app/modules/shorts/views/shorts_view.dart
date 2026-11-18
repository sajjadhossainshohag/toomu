import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../core/theme/color_constants.dart';
import '../../../core/theme/design_metrics.dart';
import '../../../services/video_session_service.dart';
import '../../youtube/controllers/youtube_controller.dart';
import '../controllers/shorts_controller.dart';

class ShortsView extends GetView<ShortsController> {
  const ShortsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ColorConstants.black,
      body: Stack(
        children: <Widget>[
          PageView.builder(
            controller: controller.pages,
            scrollDirection: Axis.vertical,
            itemCount: controller.videos.length,
            onPageChanged: controller.show,
            itemBuilder: (_, i) => _ShortPage(index: i),
          ),
          SafeArea(
            child: IconButton(
              tooltip: 'Back',
              onPressed: Get.back,
              icon: const Icon(Icons.arrow_back_rounded, color: ColorConstants.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShortPage extends GetView<ShortsController> {
  const _ShortPage({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final v = controller.videos[index];
    final yt = Get.find<YoutubeController>();
    return Obx(() {
      final current = controller.page.value == index;
      final live = controller.playing.value == v.id.value;
      final session = VideoSessionService.to;
      return Stack(
        fit: StackFit.expand,
        children: <Widget>[
          CachedNetworkImage(
            imageUrl: v.thumbnails.highResUrl,
            fit: BoxFit.cover,
            memCacheWidth: (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context)).round(),
            errorWidget: (_, _, _) => const SizedBox.shrink(),
          ),
          if (live)
            GestureDetector(
              onTap: () => session.player.playOrPause(),
              child: Video(
                controller: session.video,
                controls: NoVideoControls,
                fit: BoxFit.cover,
                fill: ColorConstants.black,
                pauseUponEnteringBackgroundMode: false,
                resumeUponEnteringForegroundMode: false,
              ),
            ),
          if (current && controller.loading.value)
            const Center(child: CircularProgressIndicator(color: ColorConstants.white)),
          if (current && controller.error.value != null)
            Center(
              child: Padding(
                padding: EdgeInsets.all(32 * scale),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      controller.error.value!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: ColorConstants.white),
                    ),
                    TextButton(onPressed: () => controller.show(index, now: true), child: const Text('Try again')),
                  ],
                ),
              ),
            ),
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Color(0x00000000), Color(0x99000000)],
                  stops: <double>[0.6, 1],
                ),
              ),
            ),
          ),
          Positioned(
            left: 16 * scale,
            right: 84 * scale,
            bottom: 28 * scale,
            child: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    v.author,
                    style: TextStyle(fontSize: 14 * scale, fontWeight: FontWeight.w700, color: ColorConstants.white),
                  ),
                  SizedBox(height: 6 * scale),
                  Text(
                    v.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5 * scale, height: 1.35, color: ColorConstants.white),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 8 * scale,
            bottom: 24 * scale,
            child: SafeArea(
              top: false,
              child: Column(
                children: <Widget>[
                  _RailButton(
                    icon: Icons.download_rounded,
                    label: 'Download',
                    onTap: () => yt.openVideo(v.id.value, known: v),
                  ),
                  _RailButton(icon: Icons.share_rounded, label: 'Share', onTap: () => yt.shareVideo(v)),
                  _RailButton(icon: Icons.link_rounded, label: 'Copy link', onTap: () => yt.copyLink(v)),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    return Padding(
      padding: EdgeInsets.only(top: 14 * scale),
      child: Column(
        children: <Widget>[
          Material(
            color: ColorConstants.black.withValues(alpha: 0.35),
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: label,
              onPressed: onTap,
              icon: Icon(icon, color: ColorConstants.white),
            ),
          ),
          SizedBox(height: 4 * scale),
          Text(
            label,
            style: TextStyle(fontSize: 11 * scale, fontWeight: FontWeight.w600, color: ColorConstants.white),
          ),
        ],
      ),
    );
  }
}
