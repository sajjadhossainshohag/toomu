import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../core/theme/color_constants.dart';

/// The app's top alert. GetX's default is see-through grey, so over the
/// header and pictures it couldn't be read; this one is solid (the app's
/// surface colour), with a shadow and the theme's text colour.
void showSnack(
  String title,
  String message, {
  Duration? duration,
  TextButton? mainButton,
}) {
  final bool dark = Get.isDarkMode;
  final Color ink = ColorConstants.textOn(dark);
  Get.snackbar(
    title,
    message,
    duration: duration ?? const Duration(seconds: 3),
    mainButton: mainButton,
    snackPosition: SnackPosition.TOP,
    backgroundColor: ColorConstants.surfaceOn(dark),
    colorText: ink,
    borderRadius: 14,
    margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    boxShadows: [
      BoxShadow(
        color: Colors.black.withValues(alpha: dark ? 0.5 : 0.18),
        blurRadius: 18,
        offset: const Offset(0, 6),
      ),
    ],
    borderColor: ink.withValues(alpha: 0.08),
    borderWidth: 1,
    titleText: Text(
      title,
      style: TextStyle(color: ink, fontSize: 14.5, fontWeight: FontWeight.w700),
    ),
    messageText: Text(
      message,
      style: TextStyle(
        color: ink.withValues(alpha: 0.78),
        fontSize: 13,
        height: 1.3,
      ),
    ),
  );
}
