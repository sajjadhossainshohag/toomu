import 'dart:math';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../services/settings_service.dart';
import '../services/video_session_service.dart';

/// The minimized video in the bottom-right corner over every screen, like YouTube's: tap to go back to it.
class FloatingVideo extends StatefulWidget {
  const FloatingVideo({super.key});

  @override
  State<FloatingVideo> createState() => _FloatingVideoState();
}

class _FloatingVideoState extends State<FloatingVideo> {
  final _session = VideoSessionService.to;
  late final AppLifecycleListener _life;

  @override
  void initState() {
    super.initState();
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
    _life.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Obx(() {
    if (!_session.minimized.value) return const SizedBox.shrink();
    final media = MediaQuery.of(context);
    final width = min(media.size.width * 0.46, 280.0);
    return Positioned(
      right: 12,
      // Above the bottom tabs.
      bottom: media.padding.bottom + 80,
      child: Material(
        color: Colors.black,
        elevation: 10,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: width,
          height: width * 9 / 16,
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
            ],
          ),
        ),
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
