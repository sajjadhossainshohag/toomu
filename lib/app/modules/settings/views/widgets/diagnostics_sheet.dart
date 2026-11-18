import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../../core/theme/color_constants.dart';
import '../../../../core/theme/design_metrics.dart';
import '../../../../services/diagnostics_service.dart';
import '../../../../services/settings_service.dart';
import '../../../../services/ytdlp_service.dart';
import '../../../../widgets/gradient_pill.dart';
import '../../../../widgets/option_sheet.dart';
import '../../../../widgets/outline_pill.dart';
import '../../../../widgets/app_snackbar.dart';

/// Recent download/yt-dlp log lines with Copy — for phones that hide logs.
class DiagnosticsSheet extends StatelessWidget {
  const DiagnosticsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final bool dark = context.isDark;
    final log = DiagnosticsService.to;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      child: AppSheet(
        title: 'Diagnostics',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Obx(() => Text(
                  'Downloader Engine ${YtDlpService.to.version.value ?? '(starting…)'} • ${log.lines.length} lines',
                  style: TextStyle(
                    fontSize: 12 * scale,
                    fontWeight: FontWeight.w600,
                    color: ColorConstants.textOn(dark).withValues(alpha: 0.6),
                  ),
                )),
            SizedBox(height: 10 * scale),
            Flexible(
              child: Container(
                decoration: BoxDecoration(
                  color: ColorConstants.groupOn(dark),
                  borderRadius: BorderRadius.circular(12 * scale),
                ),
                padding: EdgeInsets.all(10 * scale),
                child: Obx(() {
                  final lines = log.lines.reversed.toList(); // newest first
                  if (lines.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: EdgeInsets.all(24 * scale),
                        child: Text('Nothing logged yet.',
                            style: TextStyle(color: ColorConstants.textOn(dark).withValues(alpha: 0.5))),
                      ),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    itemCount: lines.length,
                    itemBuilder: (_, i) => Padding(
                      padding: EdgeInsets.only(bottom: 3 * scale),
                      child: SelectableText(
                        lines[i],
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11 * scale,
                          height: 1.35,
                          color: _colorFor(lines[i], dark),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
            if (Platform.isAndroid)
              Obx(
                () => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Direct hardware decoding (test)'),
                  subtitle: const Text('Less heat if it works. Restart the app after changing it.'),
                  value: SettingsService.to.directVideoDecoding.value,
                  onChanged: SettingsService.to.setDirectVideoDecoding,
                ),
              ),
            SizedBox(height: 12 * scale),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinePill(label: 'Clear', height: 44, onTap: log.clear),
                ),
                SizedBox(width: 12 * scale),
                Expanded(
                  child: GradientPill(
                    label: 'Copy',
                    icon: Icons.copy_rounded,
                    height: 44,
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: log.text));
                      showSnack('Copied', 'Paste it to share the diagnostics.',
                          duration: const Duration(seconds: 2));
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static Color _colorFor(String line, bool dark) {
    final l = line.toLowerCase();
    if (l.contains('error') || l.contains('failed') || l.contains('403')) return ColorConstants.error;
    if (l.contains('succeeded') || l.contains('ready')) return ColorConstants.success;
    return ColorConstants.textOn(dark).withValues(alpha: 0.75);
  }
}
