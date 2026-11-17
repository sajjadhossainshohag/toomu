import 'dart:io';

import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/utils/device_profile.dart';

class PermissionService extends GetxService {
  static PermissionService get to => Get.find();

  Future<PermissionService> init() async => this;

  int get _sdkInt => DeviceProfile.androidSdk;

  /// Read access to the device music library.
  Future<bool> requestAudio() async {
    if (!Platform.isAndroid) return true;
    final permission = _sdkInt >= 33 ? Permission.audio : Permission.storage;
    return (await permission.request()).isGranted;
  }

  /// Read access to the device's videos.
  Future<bool> requestVideo() async {
    if (!Platform.isAndroid) return true;
    final permission = _sdkInt >= 33 ? Permission.videos : Permission.storage;
    final status = await permission.request();
    return status.isGranted || status.isLimited; // limited: Android 14+ "Select videos"
  }

  /// Write access to the public Download folder. Android 10+ (scoped
  /// storage) lets apps create files there without a runtime permission.
  Future<bool> requestStorageWrite() async {
    if (!Platform.isAndroid || _sdkInt >= 29) return true;
    return (await Permission.storage.request()).isGranted;
  }

  Future<void> requestNotifications() async {
    if (Platform.isAndroid && _sdkInt >= 33) {
      await Permission.notification.request();
    }
  }
}
