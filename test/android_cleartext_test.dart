import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Android network security config is read by the WebView and by Dart's
/// HttpClient, so it decides whether http:// pages and downloads work at all.
void main() {
  test('browser opens http:// sites (no "ERR_CLEARTEXT_NOT_PERMITTED")', () {
    final xml = File('android/app/src/main/res/xml/network_security_config.xml').readAsStringSync();
    final base = RegExp(r'<base-config[^>]*>').firstMatch(xml)?.group(0) ?? '';
    expect(base, contains('cleartextTrafficPermitted="true"'));
  });
}
