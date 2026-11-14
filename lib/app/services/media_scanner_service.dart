import 'dart:io';

import 'package:flutter/services.dart';
import 'package:get/get.dart';

/// Tells Android's MediaStore about newly downloaded files so they show up
/// in the music library (ours and other apps') immediately.
/// Implemented natively in MainActivity.kt.
class MediaScannerService extends GetxService {
  static MediaScannerService get to => Get.find();

  static const _channel = MethodChannel('toomu/media_scanner');

  Future<void> scan(String path) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('scanFile', {'path': path});
    } on PlatformException catch (_) {
      // Non-fatal: the file is still playable from the Downloads tab.
    }
  }
}
