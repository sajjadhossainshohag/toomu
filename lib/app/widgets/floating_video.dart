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

  @visibleForTesting
  static Rect restRect(Size screen, EdgeInsets padding, {required bool left, double? top}) {
    final width = min(screen.width * 0.46, 280.0);
    final height = width * 9 / 16;
    final highest = padding.top + 8;
    final lowest = max(highest, screen.height - padding.bottom - 8 - height);
    // Above the bottom tabs until the user moves it.
    final y = (top ?? screen.height - padding.bottom - 80 - height).clamp(highest, lowest);
    return Rect.fromLTWH(left ? 12 : screen.width - 12 - width, y, width, height);
  }

  @visibleForTesting
  static bool landsLeft(Rect dropped, double screenWidth, double velocityX) =>
      velocityX.abs() > 800 ? velocityX < 0 : dropped.center.dx < screenWidth / 2;

  /// Which picture widget the corner video is on (a new one after each return to the app).
  @visibleForTesting
  static int surfaceOf(State<FloatingVideo> state) => (state as _FloatingVideoState)._surface;

  @override
  State<FloatingVideo> createState() => _FloatingVideoState();
}

class _FloatingVideoState extends State<FloatingVideo> with SingleTickerProviderStateMixin {
  final _session = VideoSessionService.to;
  late final AppLifecycleListener _life;
  late final AnimationController _shrink;
  late final Worker _minimizedWatch;
  Rect? _from;
  double _fromRadius = 0;
  bool _snapping = false;
  bool _left = false;
  double? _top;
  Rect _shown = Rect.zero;
  Rect? _dragged;
  int _surface = 0;

  @override
  void initState() {
    super.initState();
    _shrink = AnimationController(vsync: this, duration: const Duration(milliseconds: 300), value: 1);
    _minimizedWatch = ever(_session.minimized, (bool on) {
      _snapping = false;
      _fromRadius = 0;
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
        // Android gave the video a new surface while the app was hidden; a picture widget made before
        // kept the old layout (the video in a corner or half the box, the rest blank).
        setState(() => _surface++);
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

  void _drop(DragEndDetails d) {
    final dropped = _dragged;
    if (dropped == null) return;
    setState(() {
      _left = FloatingVideo.landsLeft(dropped, MediaQuery.sizeOf(context).width, d.velocity.pixelsPerSecond.dx);
      _top = dropped.top;
      _dragged = null;
      _from = DeviceProfile.reduceMotion ? null : dropped;
      _fromRadius = 12;
      _snapping = true;
    });
    if (_from != null) _shrink.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) => Obx(() {
    if (!_session.minimized.value) return const SizedBox.shrink();
    final media = MediaQuery.of(context);
    final rest = FloatingVideo.restRect(media.size, media.padding, left: _left, top: _top);
    return AnimatedBuilder(
      animation: _shrink,
      builder: (_, child) {
        final t = Curves.easeOutCubic.transform(_shrink.value);
        final from = _from;
        _shown = _dragged ?? (from == null ? rest : Rect.lerp(from, rest, t)!);
        return Positioned.fromRect(
          rect: _shown,
          child: Material(
            color: Colors.black,
            elevation: 10,
            borderRadius: BorderRadius.circular(
              from == null || _dragged != null ? 12 : _fromRadius + (12 - _fromRadius) * t,
            ),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
        );
      },
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Video(
            key: ValueKey(_surface),
            controller: _session.video,
            controls: NoVideoControls,
            fill: Colors.black,
            pauseUponEnteringBackgroundMode: false,
            resumeUponEnteringForegroundMode: false,
            subtitleViewConfiguration: const SubtitleViewConfiguration(visible: false),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _session.reopen,
            onPanStart: (_) => setState(() => _dragged = _shown),
            onPanUpdate: (d) => setState(() => _dragged = _dragged?.shift(d.delta)),
            onPanEnd: _drop,
          ),
          Align(
            alignment: Alignment.topRight,
            child: FadeTransition(
              opacity: _snapping ? kAlwaysCompleteAnimation : _shrink,
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
