import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/core/utils/shell_open.dart';
import 'package:toomu/app/data/providers/ytdlp/windows_ytdlp.dart';

void main() {
  group('Windows yt-dlp command line', () {
    test('points at FFmpeg and Deno and keeps the URL last', () {
      final cmd = WindowsYtDlp.commandLine(
        ['-f', 'ba', 'https://youtu.be/x'],
        ffmpegDir: r'C:\t\ffmpeg',
        deno: r'C:\t\deno.exe',
      );
      expect(cmd.last, 'https://youtu.be/x');
      expect(cmd, containsAllInOrder(['--ffmpeg-location', r'C:\t\ffmpeg']));
      expect(cmd, containsAllInOrder(['--js-runtimes', r'deno:C:\t\deno.exe']));
      expect(cmd, containsAllInOrder(['-f', 'ba']));
    });

    test('drops the Android aria2c option (no aria2c on Windows)', () {
      final cmd = WindowsYtDlp.commandLine(['--toomu-aria2c=8', '-o', 'x', 'u']);
      expect(cmd.any((a) => a.contains('aria2c')), isFalse);
      expect(cmd, containsAllInOrder(['-o', 'x', 'u']));
    });

    test('an empty URL (--load-info-json) is not passed on', () {
      final cmd = WindowsYtDlp.commandLine(['--load-info-json', 'i.json', '']);
      expect(cmd.last, 'i.json');
      expect(cmd, isNot(contains('')));
    });

    test('without FFmpeg / Deno nothing points at them', () {
      final cmd = WindowsYtDlp.commandLine(['u']);
      expect(cmd, isNot(contains('--ffmpeg-location')));
      expect(cmd, isNot(contains('--js-runtimes')));
    });

    test('lookups do not wait for FFmpeg; downloads do', () {
      expect(WindowsYtDlp.isLookup(['--dump-single-json', '--skip-download', 'u']), isTrue);
      expect(WindowsYtDlp.isLookup(['--flat-playlist', '-J', 'u']), isTrue);
      expect(WindowsYtDlp.isLookup(['-f', 'bv+ba', '-o', 'x', 'u']), isFalse);
    });
  });

  group('Windows tool install', () {
    test('release tag comes from the /releases/latest redirect', () {
      expect(WindowsYtDlp.tagFromLocation('https://github.com/yt-dlp/yt-dlp/releases/tag/2026.10.26'), '2026.10.26');
      expect(WindowsYtDlp.tagFromLocation('https://github.com/yt-dlp/yt-dlp/releases'), isNull);
      expect(WindowsYtDlp.tagFromLocation(null), isNull);
    });

    test('finds ffmpeg.exe and ffprobe.exe inside the unzipped folders', () {
      final found = WindowsYtDlp.findFiles([
        r'C:\u\out\ffmpeg-master-latest-win64-gpl\LICENSE.txt',
        r'C:\u\out\ffmpeg-master-latest-win64-gpl\bin\ffmpeg.exe',
        r'C:\u\out\ffmpeg-master-latest-win64-gpl\bin\FFprobe.exe',
        r'C:\u\out\ffmpeg-master-latest-win64-gpl\bin\ffplay.exe',
      ], {'ffmpeg.exe', 'ffprobe.exe'});
      expect(found, {
        'ffmpeg.exe': r'C:\u\out\ffmpeg-master-latest-win64-gpl\bin\ffmpeg.exe',
        'ffprobe.exe': r'C:\u\out\ffmpeg-master-latest-win64-gpl\bin\FFprobe.exe',
      });
    });
  });

  test('Explorer gets backslashes for the mixed paths downloads are saved under', () {
    expect(windowsPath(r'C:\Users\me\Downloads\Toomu/Video/Song (1080p).mp4'),
        r'C:\Users\me\Downloads\Toomu\Video\Song (1080p).mp4');
  });
}
