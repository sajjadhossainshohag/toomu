import 'dart:io';
import 'dart:ui';

import 'package:device_info_plus/device_info_plus.dart';

abstract class DeviceProfile {
  static AndroidDeviceInfo? android;
  static bool lowEnd = false;

  static int get androidSdk => android?.version.sdkInt ?? 0;

  static bool get reduceMotion =>
      PlatformDispatcher.instance.accessibilityFeatures.disableAnimations;

  static Future<void> init() async {
    if (!Platform.isAndroid) return;
    final info = android = await DeviceInfoPlugin().androidInfo;
    lowEnd = isLowEnd(
      ramMb: info.physicalRamSize,
      lowRamFlag: info.isLowRamDevice,
      sdk: info.version.sdkInt,
    );
  }

  static bool isLowEnd({required int ramMb, required bool lowRamFlag, required int sdk}) =>
      lowRamFlag || (ramMb > 0 && ramMb <= 3072) || sdk <= 27;
}
