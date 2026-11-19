import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:toomu/app/core/utils/host_os.dart';
import 'package:toomu/app/core/utils/shell_open.dart';
import 'package:toomu/app/modules/browser/media_button.dart';
import 'package:toomu/app/services/download_service.dart';

class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  @override
  Future<String?> getDownloadsPath() async => r'C:\Users\me\Downloads';

  @override
  Future<String?> getApplicationDocumentsPath() async => '/docs';
}

void main() {
  tearDown(() => HostOs.override = null);

  group('what each platform gets', () {
    test('Windows reads pages and downloads with yt-dlp, like Android', () {
      for (final os in ['android', 'windows']) {
        HostOs.override = os;
        expect(HostOs.hasYtDlp, isTrue, reason: os);
      }
      HostOs.override = 'macos';
      expect(HostOs.hasYtDlp, isFalse);
    });

    test('the browser offers "scan this page" on Windows', () {
      HostOs.override = 'windows';
      expect(mediaButtonMode(supportedPage: false, found: 0, canScan: HostOs.hasYtDlp), MediaButtonMode.scan);
    });

    test('Windows audio plays through media_kit, without the Android-only plugins', () {
      HostOs.override = 'windows';
      expect(HostOs.usesMediaKitAudio, isTrue);
      expect(HostOs.usesAudioNotification, isFalse, reason: 'just_audio_background has no Windows side');
      expect(HostOs.usesAudioSession, isFalse, reason: 'audio_session has no Windows side');

      HostOs.override = 'android';
      expect(HostOs.usesMediaKitAudio, isFalse);
      expect(HostOs.usesAudioNotification, isTrue);
      expect(HostOs.usesAudioSession, isTrue);
    });

    test('Settings names the download folder the way each system writes it', () {
      HostOs.override = 'windows';
      expect(HostOs.downloadFolderLabel, r'Downloads\Toomu');
      HostOs.override = 'android';
      expect(HostOs.downloadFolderLabel, 'Download/Toomu');
    });
  });

  group('download folder', () {
    late PathProviderPlatform saved;
    setUp(() {
      saved = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _Paths();
    });
    tearDown(() => PathProviderPlatform.instance = saved);

    test('on Windows downloads go to the Downloads folder, not the app\'s documents', () async {
      HostOs.override = 'windows';
      expect((await DownloadService.resolveRootDir()).path, r'C:\Users\me\Downloads/Toomu');
    });

    test('elsewhere (not Android) they stay in the app\'s documents', () async {
      HostOs.override = 'linux';
      expect((await DownloadService.resolveRootDir()).path, '/docs/Toomu');
    });
  });

  group('opening a finished download', () {
    final started = <(String, List<String>)>[];
    final androidOpened = <String>[];
    late Future<Object?> Function(String, List<String>) savedStart;
    late Future<Object?> Function(String) savedAndroid;

    setUp(() {
      started.clear();
      androidOpened.clear();
      savedStart = startProcess;
      savedAndroid = openWithAndroid;
      startProcess = (exe, args) async => started.add((exe, args));
      openWithAndroid = (path) async => androidOpened.add(path);
    });
    tearDown(() {
      startProcess = savedStart;
      openWithAndroid = savedAndroid;
    });

    test('Windows hands the file to Explorer with a backslash path (open_filex has no Windows side)', () async {
      HostOs.override = 'windows';
      await openFile(r'C:\Users\me\Downloads\Toomu/Audio/Song.m4a');
      expect(started.single.$1, 'explorer');
      expect(started.single.$2, [r'C:\Users\me\Downloads\Toomu\Audio\Song.m4a']);
      expect(androidOpened, isEmpty);
    });

    test('Android keeps using open_filex', () async {
      HostOs.override = 'android';
      await openFile('/storage/emulated/0/Download/Toomu/Audio/Song.m4a');
      expect(androidOpened, ['/storage/emulated/0/Download/Toomu/Audio/Song.m4a']);
      expect(started, isEmpty);
    });

    test('a file no app can open says so instead of doing nothing', () async {
      HostOs.override = 'android';
      openWithAndroid = (path) async => OpenResult(type: ResultType.noAppToOpen, message: 'No APP found to open this file');
      await expectLater(openFile('/storage/emulated/0/Download/Toomu/Files/a.xyz'), throwsA(isA<FileSystemException>()));
    });

    test('Settings "Download location" opens the folder in Explorer', () async {
      await openInExplorer(r'C:\Users\me\Downloads/Toomu');
      expect(started.single.$1, 'explorer');
      expect(started.single.$2, [r'C:\Users\me\Downloads\Toomu']);
    });
  });
}
