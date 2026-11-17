import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../core/theme/color_constants.dart';
import '../core/theme/design_metrics.dart';
import '../core/utils/device_profile.dart';
import 'app_switch.dart';
import 'gradient_pill.dart';
import 'outline_pill.dart';

/// 327pt wide, 34 radius dialog with a blurred scrim and pill actions.
Future<bool> showConfirmDialog({
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final bool? result = await Get.dialog<bool>(
    _AppDialog(
      title: title,
      message: message,
      actions: (BuildContext context) => <Widget>[
        Expanded(
          child: OutlinePill(
            label: cancelLabel,
            height: 40,
            onTap: () => Get.back(result: false),
          ),
        ),
        SizedBox(width: 13 * context.scale),
        Expanded(
          child: destructive
              ? OutlinePill(
                  label: confirmLabel,
                  height: 40,
                  tone: ColorConstants.error,
                  onTap: () => Get.back(result: true),
                )
              : GradientPill(
                  label: confirmLabel,
                  height: 40,
                  onTap: () => Get.back(result: true),
                ),
        ),
      ],
    ),
    barrierColor: ColorConstants.black.withValues(alpha: 0.4),
  );
  return result ?? false;
}

/// Destructive confirm with an optional "also delete files" switch.
/// Returns null when the user backs out.
Future<({bool deleteFiles})?> showDeleteDialog({
  required String title,
  required String message,
  String confirmLabel = 'Delete',
  String? fileToggleLabel = 'Also delete file from device',
  bool deleteFilesByDefault = true,
}) async {
  var deleteFiles = deleteFilesByDefault;
  final ok = await Get.dialog<bool>(
    StatefulBuilder(
      builder: (context, setState) {
        final double scale = context.scale;
        final Color ink = ColorConstants.textOn(context.isDark);
        return _AppDialog(
          title: title,
          message: message,
          body: fileToggleLabel == null
              ? null
              : GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => deleteFiles = !deleteFiles),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 12 * scale),
                    decoration: BoxDecoration(
                      color: ColorConstants.groupOn(context.isDark),
                      borderRadius: BorderRadius.circular(12 * scale),
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            fileToggleLabel,
                            style: TextStyle(
                              fontSize: 13.5 * scale,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0,
                              color: ink,
                            ),
                          ),
                        ),
                        SizedBox(width: 10 * scale),
                        AppSwitch(on: deleteFiles),
                      ],
                    ),
                  ),
                ),
          actions: (BuildContext context) => <Widget>[
            Expanded(
              child: OutlinePill(label: 'Cancel', height: 40, onTap: () => Get.back(result: false)),
            ),
            SizedBox(width: 13 * context.scale),
            Expanded(
              child: OutlinePill(
                label: confirmLabel,
                height: 40,
                tone: ColorConstants.error,
                onTap: () => Get.back(result: true),
              ),
            ),
          ],
        );
      },
    ),
    barrierColor: ColorConstants.black.withValues(alpha: 0.4),
  );
  return ok == true ? (deleteFiles: deleteFiles) : null;
}

Future<void> showNoticeDialog({required String title, required String message}) =>
    Get.dialog<void>(
      _AppDialog(
        title: title,
        message: message,
        actions: (_) => <Widget>[
          Expanded(child: GradientPill(label: 'OK', height: 40, onTap: Get.back)),
        ],
      ),
      barrierColor: ColorConstants.black.withValues(alpha: 0.4),
    );

/// Generic container in the dialog style for custom content.
Future<T?> showAppDialog<T>({required String title, required Widget child}) =>
    Get.dialog<T>(
      _AppDialog(title: title, body: child),
      barrierColor: ColorConstants.black.withValues(alpha: 0.4),
    );

class _AppDialog extends StatelessWidget {
  const _AppDialog({required this.title, this.message, this.body, this.actions});

  final String title;
  final String? message;
  final Widget? body;
  final List<Widget> Function(BuildContext)? actions;

  @override
  Widget build(BuildContext context) {
    final double scale = context.scale;
    final bool dark = context.isDark;
    final Color ink = ColorConstants.textOn(dark);

    return BackdropFilter(
      enabled: !DeviceProfile.lowEnd, // a full-screen blur drops frames on weak GPUs
      filter: ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24 * scale),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 327 * scale),
            child: Material(
              color: ColorConstants.surfaceOn(dark),
              borderRadius: BorderRadius.circular(34 * scale),
              child: Padding(
                padding: EdgeInsets.all(30 * scale),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16 * scale,
                        height: 20 / 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                        color: ink,
                      ),
                    ),
                    if (message != null) ...<Widget>[
                      SizedBox(height: 14 * scale),
                      Text(
                        message!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14 * scale,
                          height: 20 / 14,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0,
                          color: ink.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                    if (body != null) ...<Widget>[SizedBox(height: 14 * scale), body!],
                    if (actions != null) ...<Widget>[
                      SizedBox(height: 24 * scale),
                      Row(children: actions!(context)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
