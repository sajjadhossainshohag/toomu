import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/core/utils/app_release.dart';

void main() {
  test('dated tags update only to a later release', () {
    expect(AppRelease.isNewer('v2026.11.16-0910', 'v2026.11.15-2230'), isTrue);
    expect(AppRelease.isNewer('v2026.11.15-2230', 'v2026.11.15-2230'), isFalse);
    expect(AppRelease.isNewer('v2026.11.14-2230', 'v2026.11.15-0906'), isFalse);
  });

  test('other tags update when different; a dev build always can', () {
    expect(AppRelease.isNewer('v1.2.0', 'v2026.11.15-2230'), isTrue);
    expect(AppRelease.isNewer('v1.2.0', 'v1.2.0'), isFalse);
    expect(AppRelease.isNewer('v2026.11.15-2230', ''), isTrue);
  });

  test('picks the APK for the phone, in its order of preference', () {
    final json = {
      'tag_name': 'v2026.11.16-0910',
      'body': ' Built by CI \n',
      'assets': [
        {'name': 'debug-symbols-android.zip', 'browser_download_url': 'https://x/sym.zip', 'size': 1},
        {'name': 'toomu-armeabi-v7a.apk', 'browser_download_url': 'https://x/v7.apk', 'size': 2},
        {'name': 'toomu-arm64-v8a.apk', 'browser_download_url': 'https://x/v8.apk', 'size': 3},
      ],
    };
    final r = AppRelease.fromGitHub(json, ['arm64-v8a', 'armeabi-v7a', 'armeabi']);
    expect([r.tag, r.notes, r.apkUrl, r.apkSize], ['v2026.11.16-0910', 'Built by CI', 'https://x/v8.apk', 3]);
    expect(AppRelease.fromGitHub(json, ['armeabi-v7a', 'armeabi']).apkUrl, 'https://x/v7.apk');
    expect(AppRelease.fromGitHub(json, ['x86_64']).apkUrl, isNull);
  });
}
