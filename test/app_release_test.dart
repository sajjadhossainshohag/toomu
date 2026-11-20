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
    final r = AppRelease.fromGitHub(json, AppRelease.fileNames(windows: false, abis: ['arm64-v8a', 'armeabi-v7a', 'armeabi']));
    expect([r.tag, r.notes, r.fileUrl, r.fileSize], ['v2026.11.16-0910', 'Built by CI', 'https://x/v8.apk', 3]);
    expect(AppRelease.fromGitHub(json, AppRelease.fileNames(windows: false, abis: ['armeabi-v7a', 'armeabi'])).fileUrl, 'https://x/v7.apk');
    expect(AppRelease.fromGitHub(json, AppRelease.fileNames(windows: false, abis: ['x86_64'])).fileUrl, isNull);
  });

  test('Windows: an installed copy updates with the installer, a portable one gets the zip', () {
    final json = {
      'tag_name': 'v2026.11.20-1200',
      'assets': [
        {'name': 'toomu-arm64-v8a.apk', 'browser_download_url': 'https://x/v8.apk', 'size': 3},
        {'name': 'toomu-windows-setup.exe', 'browser_download_url': 'https://x/setup.exe', 'size': 4},
        {'name': 'toomu-windows-x64.zip', 'browser_download_url': 'https://x/win.zip', 'size': 5},
      ],
    };
    final installed = AppRelease.fromGitHub(json, AppRelease.fileNames(windows: true, installed: true));
    expect([installed.fileUrl, installed.fileSize], ['https://x/setup.exe', 4]);
    expect(AppRelease.fromGitHub(json, AppRelease.fileNames(windows: true)).fileUrl, 'https://x/win.zip');
    // Published before the Windows build attached its files: nothing to offer yet.
    final early = {'tag_name': 'v2026.11.20-1200', 'assets': (json['assets'] as List).take(1).toList()};
    expect(AppRelease.fromGitHub(early, AppRelease.fileNames(windows: true, installed: true)).fileUrl, isNull);
  });

    test('reads the latest tag from the releases page redirect when the API is rate limited', () {
    expect(AppRelease.tagFromLocation('https://github.com/a/b/releases/tag/v2026.11.16-0910'), 'v2026.11.16-0910');
    expect(AppRelease.tagFromLocation('https://github.com/a/b/releases'), isNull);
    expect(AppRelease.tagFromLocation(null), isNull);
  });
}
