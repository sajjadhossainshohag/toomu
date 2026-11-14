import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/theme/brand_colors.dart';
import '../../../core/theme/color_constants.dart';
import '../../../core/theme/design_metrics.dart';
import '../../../core/utils/formatters.dart';
import '../../../services/audio_player_service.dart';
import '../../../widgets/round_icon_button.dart';
import '../../../widgets/track_artwork.dart';
import '../controllers/player_controller.dart';

class PlayerView extends GetView<PlayerController> {
  const PlayerView({super.key});

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final bool dark = context.isDark;
    final BrandColors brand = BrandColors.of(context);
    final audio = controller.audio;
    final Color ink = ColorConstants.textOn(dark);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: Stack(
          children: <Widget>[
            // Soft brand glow behind the artwork.
            Positioned(
              top: -120 * scale,
              left: -60 * scale,
              right: -60 * scale,
              height: 460 * scale,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: <Color>[
                      brand.gradientEnd.withValues(alpha: dark ? 0.28 : 0.35),
                      brand.gradientStart.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Obx(() {
                final track = audio.current;
                if (track == null) {
                  return Center(
                    child: Text('Nothing playing',
                        style: TextStyle(color: ink.withValues(alpha: 0.6))),
                  );
                }
                return Column(
                  children: <Widget>[
                    _TopBar(controller: controller),
                    const Spacer(),
                    Hero(
                      tag: 'now-playing-art',
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28 * scale),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: brand.primary.withValues(alpha: 0.35),
                              blurRadius: 40 * scale,
                              offset: Offset(0, 16 * scale),
                            ),
                          ],
                        ),
                        child: TrackArtwork(track: track, size: 300, radius: 28, highRes: true),
                      ),
                    ),
                    const Spacer(),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24 * scale),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  track.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 22 * scale,
                                    fontWeight: FontWeight.w700,
                                    color: ink,
                                  ),
                                ),
                                SizedBox(height: 4 * scale),
                                Text(
                                  track.subtitle ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14 * scale,
                                    fontWeight: FontWeight.w500,
                                    color: ink.withValues(alpha: 0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          RoundIconButton(
                            icon: audio.favorites.contains(track.id)
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            active: audio.favorites.contains(track.id),
                            size: 44,
                            onTap: () => audio.toggleFavorite(track),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 18 * scale),
                    _SeekBar(controller: controller),
                    SizedBox(height: 10 * scale),
                    _Controls(controller: controller),
                    SizedBox(height: 22 * scale),
                    _Tools(controller: controller),
                    SizedBox(height: 16 * scale),
                  ],
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final Color ink = ColorConstants.textOn(context.isDark);
    final queue = controller.audio.queue;
    final idx = (controller.audio.currentIndex.value ?? 0) + 1;
    return Padding(
      padding: EdgeInsets.fromLTRB(12 * scale, 8 * scale, 12 * scale, 0),
      child: Row(
        children: <Widget>[
          RoundIconButton(
            icon: Icons.keyboard_arrow_down_rounded,
            size: 44,
            iconSize: 30,
            onTap: Get.back,
          ),
          Expanded(
            child: Column(
              children: <Widget>[
                Text(
                  'NOW PLAYING',
                  style: TextStyle(
                    fontSize: 11 * scale,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: ink.withValues(alpha: 0.5),
                  ),
                ),
                SizedBox(height: 2 * scale),
                Text(
                  '$idx of ${queue.length}',
                  style: TextStyle(fontSize: 13 * scale, fontWeight: FontWeight.w600, color: ink),
                ),
              ],
            ),
          ),
          RoundIconButton(
            icon: Icons.queue_music_rounded,
            size: 44,
            onTap: controller.openQueue,
            tooltip: 'Queue',
          ),
        ],
      ),
    );
  }
}

class _SeekBar extends StatelessWidget {
  const _SeekBar({required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final Color ink = ColorConstants.textOn(context.isDark);
    final audio = controller.audio;

    return Obx(() {
      final total = audio.duration.value.inMilliseconds.toDouble();
      final pos = controller.dragValue.value ??
          audio.position.value.inMilliseconds.clamp(0, total).toDouble();
      final a = audio.abStart.value, b = audio.abEnd.value;
      final TextStyle time = TextStyle(
        fontSize: 12 * scale,
        fontWeight: FontWeight.w600,
        color: ink.withValues(alpha: 0.55),
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      );
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 12 * scale),
        child: Column(
          children: <Widget>[
            Stack(
              alignment: Alignment.center,
              children: <Widget>[
                if (a != null && total > 0)
                  Positioned.fill(
                    child: LayoutBuilder(builder: (_, c) {
                      final w = c.maxWidth - 32 * scale;
                      final start = a.inMilliseconds / total;
                      final end = (b?.inMilliseconds ?? a.inMilliseconds) / total;
                      return Stack(children: <Widget>[
                        Positioned(
                          left: 16 * scale + w * start,
                          width: (w * (end - start)).clamp(2, w).toDouble(),
                          top: c.maxHeight / 2 - 6 * scale,
                          height: 12 * scale,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: ColorConstants.warning.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(4 * scale),
                            ),
                          ),
                        ),
                      ]);
                    }),
                  ),
                Slider(
                  value: total <= 0 ? 0 : pos,
                  max: total <= 0 ? 1 : total,
                  onChanged: total <= 0 ? null : controller.onSeekChanged,
                  onChangeEnd: total <= 0 ? null : controller.onSeekEnd,
                ),
              ],
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12 * scale),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(Formatters.duration(Duration(milliseconds: pos.round())), style: time),
                  Text(Formatters.duration(audio.duration.value), style: time),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final audio = controller.audio;
    return Obx(() {
      final loading = audio.processing.value == ProcessingState.loading ||
          audio.processing.value == ProcessingState.buffering;
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: <Widget>[
          RoundIconButton(
            icon: Icons.shuffle_rounded,
            size: 44,
            active: audio.shuffle.value,
            onTap: audio.toggleShuffle,
          ),
          RoundIconButton(
            icon: Icons.skip_previous_rounded,
            size: 52,
            iconSize: 34,
            onTap: audio.previous,
          ),
          SizedBox.square(
            dimension: 76 * context.scale,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                RoundIconButton(
                  icon: audio.playing.value ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 76,
                  iconSize: 40,
                  filled: true,
                  onTap: audio.togglePlay,
                ),
                if (loading)
                  IgnorePointer(
                    child: SizedBox.square(
                      dimension: 80 * context.scale,
                      child: const CircularProgressIndicator(
                          strokeWidth: 2, color: ColorConstants.white),
                    ),
                  ),
              ],
            ),
          ),
          RoundIconButton(
            icon: Icons.skip_next_rounded,
            size: 52,
            iconSize: 34,
            onTap: audio.next,
          ),
          RoundIconButton(
            icon: audio.loopMode.value == LoopMode.one
                ? Icons.repeat_one_rounded
                : Icons.repeat_rounded,
            size: 44,
            active: audio.loopMode.value != LoopMode.off,
            onTap: audio.cycleLoopMode,
          ),
        ],
      );
    });
  }
}

/// MX-style tool strip: rewind/forward 10s, speed, sleep, A-B, equalizer.
class _Tools extends StatelessWidget {
  const _Tools({required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final bool dark = context.isDark;
    final audio = controller.audio;

    return Obx(
      () => Container(
        margin: EdgeInsets.symmetric(horizontal: 16 * scale),
        padding: EdgeInsets.symmetric(vertical: 6 * scale, horizontal: 6 * scale),
        decoration: BoxDecoration(
          color: ColorConstants.groupOn(dark),
          borderRadius: BorderRadius.circular(20 * scale),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: <Widget>[
            RoundIconButton(
              icon: Icons.replay_10_rounded,
              size: 46,
              onTap: () => audio.seekRelative(-10),
            ),
            RoundIconButton(
              icon: Icons.speed_rounded,
              size: 46,
              badge: '${audio.speed.value.toStringAsFixed(audio.speed.value % 1 == 0 ? 0 : 2)}x',
              active: audio.speed.value != 1.0 || audio.pitch.value != 1.0,
              onTap: controller.openSpeed,
            ),
            RoundIconButton(
              icon: Icons.bedtime_rounded,
              size: 46,
              badge: controller.sleepLabel,
              active: audio.sleepMode.value != SleepMode.off,
              onTap: controller.openSleepTimer,
            ),
            RoundIconButton(
              icon: Icons.repeat_on_rounded,
              size: 46,
              badge: controller.abLabel,
              active: audio.abStart.value != null,
              onTap: audio.cycleAbRepeat,
            ),
            RoundIconButton(
              icon: Icons.equalizer_rounded,
              size: 46,
              badge: 'EQ',
              active: audio.equalizerEnabled.value,
              onTap: controller.openEqualizer,
            ),
            RoundIconButton(
              icon: Icons.forward_10_rounded,
              size: 46,
              onTap: () => audio.seekRelative(10),
            ),
          ],
        ),
      ),
    );
  }
}
