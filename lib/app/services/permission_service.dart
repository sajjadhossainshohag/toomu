import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionService extends GetxService {
  static PermissionService get to => Get.find();

  int _sdkInt = 0;

  Future<PermissionService> init() async {
    if (Platform.isAndroid) {
      _sdkInt = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    }
    return this;
  }

  int get androidSdk => _sdkInt;

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
    return (await permission.request()).isGranted;
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
