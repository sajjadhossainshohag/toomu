import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';

import '../../../../core/theme/color_constants.dart';
import '../../../../core/theme/design_metrics.dart';
import '../../../../services/audio_player_service.dart';
import '../../../../widgets/app_switch.dart';
import '../../../../widgets/info_banner.dart';
import '../../../../widgets/option_sheet.dart';
import '../../../../widgets/outline_pill.dart';

class EqualizerSheet extends StatelessWidget {
  const EqualizerSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final audio = AudioPlayerService.to;
    final double scale = context.scale;

    return AppSheet(
      title: 'Equalizer',
      trailing: Obx(
        () => GestureDetector(
          onTap: () => audio.setEqualizerEnabled(!audio.equalizerEnabled.value),
          child: AppSwitch(on: audio.equalizerEnabled.value),
        ),
      ),
      child: FutureBuilder<AndroidEqualizerParameters?>(
        future: audio.equalizerParameters(),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return Padding(
              padding: EdgeInsets.all(24 * scale),
              child: const Center(child: CircularProgressIndicator()),
            );
          }
          final params = snap.data;
          if (params == null) {
            return const InfoBanner('Equalizer is available on Android only.');
          }
          final size = MediaQuery.sizeOf(context);
          // Shorter bars in landscape so the sheet fits the short screen.
          final barHeight = size.width > size.height
              ? (size.height * 0.4).clamp(120.0, 220.0)
              : 220.0;
          return Obx(
            () => SingleChildScrollView(
              child: Opacity(
                opacity: audio.equalizerEnabled.value ? 1 : 0.45,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    SizedBox(
                      height: barHeight * scale,
                      child: Row(
                        children: <Widget>[
                          for (final band in params.bands)
                            Expanded(
                              child: _BandSlider(
                                band: band,
                                min: params.minDecibels,
                                max: params.maxDecibels,
                                enabled: audio.equalizerEnabled.value,
                                onChanged: (g) => audio.setBandGain(band, g),
                              ),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(height: 12 * scale),
                    OutlinePill(
                      label: 'Reset to flat',
                      height: 42,
                      onTap: audio.resetEqualizer,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BandSlider extends StatelessWidget {
  const _BandSlider({
    required this.band,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onChanged,
  });

  final AndroidEqualizerBand band;
  final double min;
  final double max;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final Color ink = ColorConstants.textOn(context.isDark);
    final hz = band.centerFrequency;
    final label = hz >= 1000
        ? '${(hz / 1000).toStringAsFixed(hz >= 10000 ? 0 : 1)}k'
        : '${hz.round()}';

    return StreamBuilder<double>(
      stream: band.gainStream,
      builder: (_, snap) {
        final gain = snap.data ?? band.gain;
        return Column(
          children: <Widget>[
            Text(
              '${gain > 0 ? '+' : ''}${gain.toStringAsFixed(0)}',
              style: TextStyle(
                fontSize: 11 * scale,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
            Expanded(
              child: RotatedBox(
                quarterTurns: 3,
                child: Slider(
                  value: gain.clamp(min, max),
                  min: min,
                  max: max,
                  onChanged: enabled ? onChanged : null,
                ),
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 11 * scale,
                fontWeight: FontWeight.w600,
                color: ink.withValues(alpha: 0.55),
              ),
            ),
          ],
        );
      },
    );
  }
}
