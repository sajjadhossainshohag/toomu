import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/theme/brand_colors.dart';
import '../../../../core/theme/color_constants.dart';
import '../../../../core/theme/design_metrics.dart';
import '../../../../services/audio_player_service.dart';
import '../../../../widgets/option_sheet.dart';
import '../../../../widgets/outline_pill.dart';

class SpeedSheet extends StatelessWidget {
  const SpeedSheet({super.key});

  static const presets = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  Widget build(BuildContext context) {
    final audio = AudioPlayerService.to;
    final double scale = context.scale;
    final bool dark = context.isDark;
    final Color ink = ColorConstants.textOn(dark);
    final BrandColors brand = BrandColors.of(context);

    Widget label(String text, String value) => Row(
      children: <Widget>[
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14 * scale,
              fontWeight: FontWeight.w600,
              color: ink,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14 * scale,
            fontWeight: FontWeight.w700,
            color: brand.primary,
          ),
        ),
      ],
    );

    return AppSheet(
      title: 'Playback speed',
      child: Obx(
        () => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Wrap(
                spacing: 8 * scale,
                runSpacing: 8 * scale,
                children: <Widget>[
                  for (final p in presets)
                    GestureDetector(
                      onTap: () => audio.setSpeed(p),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 92 * scale,
                        height: 38 * scale,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: audio.speed.value == p
                              ? brand.pillGradient
                              : null,
                          color: audio.speed.value == p
                              ? null
                              : ColorConstants.groupOn(dark),
                          borderRadius: BorderRadius.circular(12 * scale),
                        ),
                        child: Text(
                          '${p}x',
                          style: TextStyle(
                            fontSize: 13 * scale,
                            fontWeight: FontWeight.w700,
                            color: audio.speed.value == p
                                ? ColorConstants.white
                                : ink.withValues(alpha: 0.75),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(height: 18 * scale),
              label('Speed', '${audio.speed.value.toStringAsFixed(2)}x'),
              Slider(
                value: audio.speed.value.clamp(0.25, 3.0),
                min: 0.25,
                max: 3.0,
                divisions: 55,
                onChanged: audio.setSpeed,
              ),
              label('Pitch', '${audio.pitch.value.toStringAsFixed(2)}x'),
              Slider(
                value: audio.pitch.value.clamp(0.5, 2.0),
                min: 0.5,
                max: 2.0,
                divisions: 30,
                onChanged: audio.setPitch,
              ),
              SizedBox(height: 8 * scale),
              OutlinePill(
                label: 'Reset',
                height: 42,
                onTap: () {
                  audio.setSpeed(1);
                  audio.setPitch(1);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
