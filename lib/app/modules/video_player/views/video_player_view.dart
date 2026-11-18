import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../core/theme/brand_colors.dart';
import '../../../core/theme/color_constants.dart';
import '../../../core/utils/formatters.dart';
import '../controllers/video_playback_controller.dart';
import 'watch_details.dart';

/// Full-screen MX-style player.
class VideoPlayerView extends GetView<VideoPlaybackController> {
  const VideoPlayerView({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Locked: back does nothing (like MX); unlock first.
        if (controller.locked.value) {
          controller.showControls();
          return;
        }
        controller.exit();
      },
      child: Scaffold(
        backgroundColor: ColorConstants.black,
        body: LayoutBuilder(
          builder: (context, constraints) => Obx(() {
            final String? youtubeId = controller.items.isEmpty ? null : controller.current.youtubeId;
            // Upright with a YouTube video: the player on top and the watch page under it, like YouTube.
            final bool watch =
                youtubeId != null && constraints.maxHeight > constraints.maxWidth && !controller.inPip.value;
            // Like YouTube: the player takes the video's shape, from 16:9 (wider videos are letterboxed) to 4:5.
            final double aspect = (controller.videoAspect.value ?? 16 / 9).clamp(4 / 5, 16 / 9);
            final Size box = watch ? Size(constraints.maxWidth, constraints.maxWidth / aspect) : constraints.biggest;
            controller.viewSize = box;
            controller.screenSize = constraints.biggest;
            // The status bar shows over the watch page, like YouTube; full screen hides the bars.
            controller.showSystemBars(watch);
            final player = SizedBox.fromSize(
              size: box,
              child: _player(context, box, watch, constraints.maxWidth > constraints.maxHeight),
            );
            if (!watch) return player;
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle.light,
              child: Column(
                children: <Widget>[
                  // The box is at the top: the screen's bottom inset (gesture bar) belongs to the details below.
                  // removeTop too: this context is outside the SafeArea, so its padding still has the cutout,
                  // and the top bar would move down by it a second time.
                  SafeArea(
                    bottom: false,
                    child: MediaQuery.removePadding(
                      context: context,
                      removeTop: true,
                      removeBottom: true,
                      child: player,
                    ),
                  ),
                  Expanded(
                    child: WatchDetails(key: ValueKey(youtubeId), videoId: youtubeId),
                  ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }

  // Our own size and scaler: media_kit's default shrinks captions by sqrt(box area / 1920×1080), ~6 px in the
  // small player. YouTube's look: white on a dark box, ~15 px upright, ~21 px full screen on a phone.
  static SubtitleViewConfiguration captions(Size box, TextScaler system) => SubtitleViewConfiguration(
    style: TextStyle(
      fontSize: (box.shortestSide * 0.055).clamp(15.0, 28.0),
      height: 1.3,
      color: Colors.white,
      fontWeight: FontWeight.w500,
      backgroundColor: const Color(0xBF080808),
    ),
    textScaler: system,
    padding: EdgeInsets.fromLTRB(16, 0, 16, box.shortestSide * 0.06),
  );

  Widget _player(BuildContext context, Size box, bool compact, bool landscape) => Stack(
    fit: StackFit.expand,
    children: <Widget>[
      // Video (zoom = pinch; fit/aspect = aspect button).
      Obx(
        () => controller.exiting.value
            ? const SizedBox.expand()
            : ClipRect(
                child: Transform.scale(
                  scale: controller.zoom.value,
                  child: Video(
                    // A fresh surface per orientation: some phones kept
                    // the old layout after turning (half the picture).
                    key: ValueKey(landscape),
                    controller: controller.video,
                    controls: NoVideoControls,
                    fill: ColorConstants.black,
                    // The controller decides (PiP / background play / pause).
                    pauseUponEnteringBackgroundMode: false,
                    resumeUponEnteringForegroundMode: false,
                    fit: controller.fit.value.boxFit,
                    aspectRatio: controller.fit.value.aspect,
                    subtitleViewConfiguration: captions(box, MediaQuery.textScalerOf(context)),
                  ),
                ),
              ),
      ),

      // Everything below is hidden in picture-in-picture.
      Obx(
        () => controller.inPip.value
            ? const SizedBox.shrink()
            : Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  // Gestures.
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: controller.onTap,
                    onDoubleTapDown: controller.onDoubleTapDown,
                    onDoubleTap: controller.onDoubleTap,
                    onScaleStart: controller.onScaleStart,
                    onScaleUpdate: controller.onScaleUpdate,
                    onScaleEnd: controller.onScaleEnd,
                  ),

                  const _SkipRipples(),
                  // With the controls up, the play/pause button is the loader.
                  Obx(
                    () => controller.buffering.value && !controller.controlsVisible.value
                        ? const Center(child: CircularProgressIndicator(color: Colors.white))
                        : const SizedBox.shrink(),
                  ),
                  _Controls(compact: compact),
                  const _GestureFeedbackCard(),
                  _ResumedChip(compact: compact),
                ],
              ),
      ),
    ],
  );
}

// ------------------------------------------------------------------ controls

class _Controls extends GetView<VideoPlaybackController> {
  const _Controls({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final visible = controller.controlsVisible.value;
      final locked = controller.locked.value;
      return IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: visible ? 1 : 0,
          child: locked ? const _LockedOverlay() : _FullControls(compact: compact),
        ),
      );
    });
  }
}

class _LockedOverlay extends GetView<VideoPlaybackController> {
  const _LockedOverlay();

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 24),
        child: _CircleButton(icon: Icons.lock_rounded, onTap: controller.toggleLock, size: 54),
      ),
    ),
  );
}

class _FullControls extends GetView<VideoPlaybackController> {
  const _FullControls({required this.compact});

  // The small player above the watch page: the title is below it, and full screen replaces lock/aspect.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    const scrim = [Color(0xB3000000), Color(0x00000000)];
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // Top bar.
        Align(
          alignment: Alignment.topCenter,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: scrim),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(4, 4, 8, compact ? 4 : 24),
                child: Row(
                  children: <Widget>[
                    IconButton(
                      // Not Get.back: that closes at once, turning the
                      // screen upright during the close animation.
                      onPressed: controller.exit,
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                    ),
                    if (compact)
                      const Spacer()
                    else
                      Expanded(
                        child: Obx(
                          () => Text(
                            controller.current.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    // YouTube streams: quality menu.
                    Obx(() {
                      if (controller.items.isEmpty) return const SizedBox.shrink();
                      final item = controller.current;
                      if (item.qualities.isEmpty) return const SizedBox.shrink();
                      return _TextButton(
                        label: item.currentQuality?.label ?? item.quality ?? 'Quality',
                        onTap: controller.pickQuality,
                      );
                    }),
                    Obx(
                      () => _TextButton(
                        label: controller.rate.value == 1 ? '1x' : '${controller.rate.value}x',
                        onTap: controller.pickSpeed,
                      ),
                    ),
                    Obx(
                      () => _IconAction(
                        icon: controller.backgroundPlay.value ? Icons.headphones_rounded : Icons.headset_off_rounded,
                        onTap: controller.toggleBackgroundPlay,
                        tooltip: 'Background play',
                        active: controller.backgroundPlay.value,
                      ),
                    ),
                    Obx(
                      () => controller.pipSupported.value
                          ? _IconAction(
                              icon: Icons.picture_in_picture_alt_rounded,
                              onTap: controller.enterPip,
                              tooltip: 'Picture-in-picture',
                            )
                          : const SizedBox.shrink(),
                    ),
                    _IconAction(icon: Icons.audiotrack_rounded, onTap: controller.pickAudioTrack, tooltip: 'Audio'),
                    _IconAction(icon: Icons.subtitles_rounded, onTap: controller.pickSubtitle, tooltip: 'Subtitles'),
                    _IconAction(icon: Icons.screen_rotation_rounded, onTap: controller.rotate, tooltip: 'Rotate'),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Centre play/pause + prev/next.
        Center(
          child: Obx(
            () => Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _CircleButton(icon: Icons.skip_previous_rounded, onTap: controller.previous, size: compact ? 40 : 48),
                SizedBox(width: compact ? 22 : 28),
                _CircleButton(
                  icon: controller.playing.value ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  onTap: controller.playPause,
                  size: compact ? 54 : 68,
                  filled: true,
                  busy: controller.buffering.value,
                ),
                SizedBox(width: compact ? 22 : 28),
                _CircleButton(
                  icon: Icons.skip_next_rounded,
                  onTap: controller.hasNext ? controller.next : null,
                  size: compact ? 40 : 48,
                ),
              ],
            ),
          ),
        ),

        // Bottom bar: seek bar + lock / aspect.
        Align(
          alignment: Alignment.bottomCenter,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: scrim),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(12, compact ? 4 : 24, compact ? 4 : 12, compact ? 0 : 8),
                child: compact
                    // In a Column like the full layout's: in a bare Row the Slider takes the whole player's height.
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              const Expanded(child: _SeekBar()),
                              _IconAction(
                                icon: Icons.fullscreen_rounded,
                                onTap: controller.rotate,
                                tooltip: 'Full screen',
                              ),
                            ],
                          ),
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const _SeekBar(),
                          Row(
                            children: <Widget>[
                              _IconAction(icon: Icons.lock_open_rounded, onTap: controller.toggleLock, tooltip: 'Lock'),
                              const Spacer(),
                              Obx(
                                () => _IconAction(
                                  icon: controller.fit.value.icon,
                                  onTap: controller.cycleFit,
                                  tooltip: 'Aspect: ${controller.fit.value.label}',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SeekBar extends GetView<VideoPlaybackController> {
  const _SeekBar();

  @override
  Widget build(BuildContext context) {
    const time = TextStyle(
      color: Colors.white,
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    return Obx(() {
      final total = controller.duration.value.inMilliseconds.toDouble();
      final pos = controller.position.value.inMilliseconds.clamp(0, total).toDouble();
      return Row(
        children: <Widget>[
          Text(Formatters.duration(controller.position.value), style: time),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: BrandColors.of(context).accent,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
              ),
              child: Slider(
                value: total <= 0 ? 0 : pos,
                max: total <= 0 ? 1 : total,
                onChanged: total <= 0 ? null : (v) => controller.previewSeek(Duration(milliseconds: v.round())),
                onChangeEnd: total <= 0 ? null : (v) => controller.seekTo(Duration(milliseconds: v.round())),
              ),
            ),
          ),
          Text(Formatters.duration(controller.duration.value), style: time),
        ],
      );
    });
  }
}

// ------------------------------------------------------------------ overlays

class _GestureFeedbackCard extends GetView<VideoPlaybackController> {
  const _GestureFeedbackCard();

  @override
  Widget build(BuildContext context) => Obx(() {
    final f = controller.feedback.value;
    if (f == null) return const SizedBox.shrink();
    return Center(
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(f.icon, color: Colors.white, size: 30),
              const SizedBox(height: 8),
              Text(
                f.text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              if (f.level != null) ...<Widget>[
                const SizedBox(height: 10),
                SizedBox(
                  width: 140,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: f.level,
                      minHeight: 5,
                      backgroundColor: Colors.white24,
                      color: BrandColors.of(context).accent,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  });
}

class _SkipRipples extends GetView<VideoPlaybackController> {
  const _SkipRipples();

  @override
  Widget build(BuildContext context) => Obx(() {
    final s = controller.skipRipple.value;
    if (s == 0) return const SizedBox.shrink();
    final forward = s > 0;
    return IgnorePointer(
      child: Align(
        alignment: forward ? Alignment.centerRight : Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: 0.35,
          heightFactor: 1,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.horizontal(
                left: forward ? const Radius.circular(400) : Radius.zero,
                right: forward ? Radius.zero : const Radius.circular(400),
              ),
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(forward ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded, color: Colors.white, size: 34),
                const SizedBox(height: 4),
                Text(
                  '${forward ? '+' : '−'}${s.abs()}s',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  });
}

class _ResumedChip extends GetView<VideoPlaybackController> {
  const _ResumedChip({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) => Obx(() {
    final from = controller.resumedFrom.value;
    if (from == null) return const SizedBox.shrink();
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomLeft,
        child: Padding(
          padding: EdgeInsets.fromLTRB(compact ? 12 : 20, 0, 20, compact ? 48 : 110),
          child: Material(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'Resumed from ${Formatters.duration(from)}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 6),
                  TextButton(
                    onPressed: controller.startOver,
                    child: Text('Start over', style: TextStyle(color: BrandColors.of(context).accent)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  });
}

// ------------------------------------------------------------------- buttons

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.onTap,
    this.size = 48,
    this.filled = false,
    this.busy = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final bool filled;
  final bool busy;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onTap == null ? 0.4 : 1,
    child: Material(
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: filled ? BrandColors.of(context).pillGradient : null,
          color: filled ? null : Colors.black.withValues(alpha: 0.35),
        ),
        child: InkWell(
          onTap: onTap,
          child: SizedBox.square(
            dimension: size,
            child: busy
                ? Padding(
                    padding: EdgeInsets.all(size * 0.25),
                    child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                  )
                : Icon(icon, color: Colors.white, size: size * 0.55),
          ),
        ),
      ),
    ),
  );
}

class _IconAction extends StatelessWidget {
  const _IconAction({required this.icon, required this.onTap, this.tooltip, this.active = false});

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  /// Toggled-on state (e.g. background play) is drawn in the brand accent.
  final bool active;

  @override
  // Compact (36 dp) so the top bar's seven actions + title fit a portrait
  // phone without overflowing.
  Widget build(BuildContext context) => IconButton(
    onPressed: onTap,
    tooltip: tooltip,
    visualDensity: VisualDensity.compact,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: 36, height: 40),
    iconSize: 22,
    icon: Icon(icon, color: active ? BrandColors.of(context).accent : Colors.white),
  );
}

class _TextButton extends StatelessWidget {
  const _TextButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onTap,
    // TextButton's default 64 dp minimum width is too wide for the bar.
    style: TextButton.styleFrom(
      minimumSize: const Size(40, 40),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    child: Text(
      label,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
    ),
  );
}
