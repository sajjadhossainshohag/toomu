import 'dart:math';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../core/utils/device_profile.dart';
import '../services/settings_service.dart';
import '../services/video_session_service.dart';

/// The minimized video in the bottom-right corner over every screen, like YouTube's: tap to go back to it.
class FloatingVideo extends StatefulWidget {
  const FloatingVideo({super.key});

  @override
  State<FloatingVideo> createState() => _FloatingVideoState();
}

class _FloatingVideoState extends State<FloatingVideo> with SingleTickerProviderStateMixin {
  final _session = VideoSessionService.to;
  late final AppLifecycleListener _life;
  late final _shrink = AnimationController(vsync: this, duration: const Duration(milliseconds: 300), value: 1);
  late final Worker _minimizedWatch;
  Rect? _from;

  @override
  void initState() {
    super.initState();
    _minimizedWatch = ever(_session.minimized, (bool on) {
      _from = on && !DeviceProfile.reduceMotion ? _session.minimizeFrom : null;
      _session.minimizeFrom = null;
      _from == null ? _shrink.value = 1 : _shrink.forward(from: 0);
    });
    // Same rule as the full player: leaving the app pauses, unless background play is on (then audio only).
    _life = AppLifecycleListener(
      onPause: () {
        if (!_session.minimized.value) return;
        if (SettingsService.to.videoBackgroundPlay.value) {
          _session.setVideoEnabled(false);
        } else {
          _session.player.pause();
        }
      },
      onResume: () {
        if (_session.minimized.value) _session.setVideoEnabled(true);
      },
    );
  }

  @override
  void dispose() {
    _minimizedWatch.dispose();
    _shrink.dispose();
    _life.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Obx(() {
    if (!_session.minimized.value) return const SizedBox.shrink();
    final media = MediaQuery.of(context);
    final width = min(media.size.width * 0.46, 280.0);
    final height = width * 9 / 16;
    // Above the bottom tabs.
    final corner = Rect.fromLTWH(
      media.size.width - 12 - width,
      media.size.height - media.padding.bottom - 80 - height,
      width,
      height,
    );
    return AnimatedBuilder(
      animation: _shrink,
      builder: (_, child) {
        final t = Curves.easeOutCubic.transform(_shrink.value);
        final from = _from;
        return Positioned.fromRect(
          rect: from == null ? corner : Rect.lerp(from, corner, t)!,
          child: Material(
            color: Colors.black,
            elevation: 10,
            borderRadius: BorderRadius.circular(from == null ? 12 : 12 * t),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
        );
      },
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Video(
            controller: _session.video,
            controls: NoVideoControls,
            fill: Colors.black,
            pauseUponEnteringBackgroundMode: false,
            resumeUponEnteringForegroundMode: false,
            subtitleViewConfiguration: const SubtitleViewConfiguration(visible: false),
          ),
          GestureDetector(behavior: HitTestBehavior.opaque, onTap: _session.reopen),
          Align(
            alignment: Alignment.topRight,
            child: FadeTransition(
              opacity: _shrink,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Obx(
                    () => _Button(
                      icon: _session.playing.value ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      label: _session.playing.value ? 'Pause' : 'Play',
                      onTap: _session.player.playOrPause,
                    ),
                  ),
                  _Button(icon: Icons.close_rounded, label: 'Close', onTap: _session.stop),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  });
}

class _Button extends StatelessWidget {
  const _Button({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: InkResponse(
      onTap: onTap,
      radius: 20,
      child: Container(
        margin: const EdgeInsets.all(4),
        padding: const EdgeInsets.all(4),
        decoration: const BoxDecoration(color: Color(0x99000000), shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    ),
  );
}
