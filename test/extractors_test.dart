import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';
import 'package:toomu/app/data/models/download_task.dart';
import 'package:toomu/app/data/models/media_format.dart';
import 'package:toomu/app/data/models/yt_info.dart';
import 'package:toomu/app/data/providers/ytdlp/ytdlp_bridge.dart';
import 'package:toomu/app/extractors/direct_file_extractor.dart';
import 'package:toomu/app/extractors/media_extractor.dart';
import 'package:toomu/app/services/ytdlp_service.dart';

/// Trimmed shape of real `yt-dlp --dump-single-json` output.
YtInfo _info() => YtInfo.fromJson({
      'id': 'abcdefghijk',
      'title': 'Song',
      'uploader': 'Artist',
      'duration': 200,
      'formats': [
        {'format_id': '140', 'ext': 'm4a', 'vcodec': 'none', 'acodec': 'mp4a.40.2', 'abr': 129.5, 'filesize': 3200000, 'language_preference': 10, 'url': 'https://a/140', 'http_headers': {'User-Agent': 'x'}},
        {'format_id': '140-1', 'ext': 'm4a', 'vcodec': 'none', 'acodec': 'mp4a.40.2', 'abr': 130.0, 'filesize': 3300000, 'language_preference': -1},
        {'format_id': '251', 'ext': 'webm', 'vcodec': 'none', 'acodec': 'opus', 'abr': 135.0, 'filesize': 3400000, 'language_preference': 10},
        {'format_id': '137', 'ext': 'mp4', 'vcodec': 'avc1.640028', 'acodec': 'none', 'height': 1080, 'filesize': 80000000},
        {'format_id': '313', 'ext': 'webm', 'vcodec': 'vp9', 'acodec': 'none', 'height': 2160, 'filesize': 300000000},
        {'format_id': '18', 'ext': 'mp4', 'vcodec': 'avc1.42001E', 'acodec': 'mp4a.40.2', 'height': 360, 'filesize_approx': 10000000},
      ],
    });

void main() {
  group('YtInfo', () {
    test('best audio is the original-language AAC track, not a dub', () {
      final a = _info().bestAudio!;
      expect(a.formatId, '140');
      expect(a.httpHeaders['User-Agent'], 'x');
    });

    test('duration and uploader parse', () {
      final i = _info();
      expect(i.duration, const Duration(seconds: 200));
      expect(i.uploader, 'Artist');
    });
  });

  group('MediaFormat', () {
    test('one video option per height, best first, saved as MP4', () {
      final v = MediaFormat.videoOptions(_info());
      expect(v.map((f) => f.label), ['2160p', '1080p', '360p'], reason: 'the p-number stays: it goes into file names');
      expect(v.every((f) => f.extension == 'mp4'), isTrue);
      expect(v[1].selector, startsWith('bv*[height<=1080]'));
    });

    test('qualities have plain names and hints, no codec jargon', () {
      final v = MediaFormat.videoOptions(_info());
      expect(v.map((f) => f.name), ['4K Ultra HD', 'Full HD', 'Low']);
      expect(v.map((f) => f.detail).join(), isNot(matches(RegExp('H.264|VP9|AV1|MP4'))));
      expect(v[2].detail, 'Saves more data');
    });

    test('a quality with no H.264 stream warns it may not play on older phones', () {
      final v = MediaFormat.videoOptions(_info());
      expect(v[0].mayNotPlay, isTrue, reason: '2160p is VP9 only');
      expect(v[0].detail, 'May not play on older phones');
      expect(v[1].mayNotPlay, isFalse);
    });

    test('audio: MP3 that plays everywhere and the original M4A; no MP3 320 (the source is ~130 kbps)', () {
      final a = MediaFormat.audioOptions(_info());
      expect(a.map((f) => f.convert), ['mp3:192', null]);
      expect(a.map((f) => f.name), ['MP3', 'Original audio']);
      expect(a.first.sizeBytes, 200 * 192 * 1000 ~/ 8);
      expect(a.last.detail, 'Best sound, smallest file (M4A)');
    });

    test('the recommended quality: the last one picked, else Full HD, else the best below it', () {
      final v = MediaFormat.videoOptions(_info()); // 2160p, 1080p, 360p
      expect(MediaFormat.recommended(v, 1080)?.label, '1080p');
      expect(MediaFormat.recommended(v, 2160)?.label, '2160p');
      expect(MediaFormat.recommended(v, 720)?.label, '360p');
      expect(MediaFormat.recommended([v.first], 1080)?.label, '2160p', reason: 'only a bigger one: still offered');
      expect(MediaFormat.recommended(const [], 1080), isNull);
    });

    test('four qualities up front, 1080p to 360p; 4K, 2K and the tiny ones under "More"', () {
      List<MediaFormat> of(List<int> qs) => [
            for (final q in qs) MediaFormat(kind: DownloadKind.video, label: '${q}p', extension: 'mp4', sizeBytes: 0, detail: '', selector: '', height: q),
          ];
      final all = MediaFormat.firstFour(of([2160, 1440, 1080, 720, 480, 360, 240, 144]));
      expect(all.first.map((f) => f.height), [1080, 720, 480, 360]);
      expect(all.more.map((f) => f.height), [2160, 1440, 240, 144]);

      final few = MediaFormat.firstFour(of([2160, 1440, 1080, 360, 144]));
      expect(few.first.map((f) => f.height), [2160, 1440, 1080, 360], reason: 'the nearest others fill the four');
      expect(few.more.map((f) => f.height), [144]);
    });
  });

  test('legacy tasks map their itags to a yt-dlp selector', () {
    final t = DownloadTask(id: '1', title: 't', kind: DownloadKind.video, extension: 'mp4', filePath: '/x.mp4', createdAt: DateTime(2026), streamTag: 137, audioTag: 140);
    expect(t.ytdlpFormat, '137+140/bv*+ba/b');
  });

  test('YtDlpException keeps the last ERROR line without prefixes', () {
    final e = YtDlpException('WARNING: x\nERROR: [youtube] abcdefghijk: Sign in to confirm you’re not a bot\n');
    expect(e.message, 'Sign in to confirm you’re not a bot');
  });

  group('DirectFileExtractor', () {
    const e = DirectFileExtractor();
    test('handles media and file links', () {
      expect(e.canHandle(Uri.parse('https://cdn.example.com/a/song.mp3')), isTrue);
      expect(e.canHandle(Uri.parse('https://cdn.example.com/clip.MP4?token=1')), isTrue);
      expect(e.canHandle(Uri.parse('https://example.com/file.pdf')), isTrue);
    });
    test('ignores pages and non-http links', () {
      expect(e.canHandle(Uri.parse('https://example.com/watch')), isFalse);
      expect(e.canHandle(Uri.parse('https://example.com/page.html')), isFalse);
      expect(e.canHandle(Uri.parse('ftp://example.com/song.mp3')), isFalse);
    });
  });

  test('SiteShortcut parses remote config entries', () {
    final s = SiteShortcut.fromJson({'name': 'YouTube', 'url': 'https://m.youtube.com/', 'icon': 'video', 'color': '#FF0033'});
    expect(s.icon, Iconsax.video_play_copy, reason: 'same outline icons as the bottom nav');
    expect(s.color, const Color(0xFFFF0033));
  });

  test('403 / bot-check errors trigger the client fallback; private videos do not', () {
    expect(YtDlpService.isRetryable('ERROR: unable to download video data: HTTP Error 403: Forbidden'), isTrue);
    expect(YtDlpService.isRetryable("ERROR: [youtube] x: Sign in to confirm you're not a bot"), isTrue);
    expect(YtDlpService.isRetryable('ERROR: [youtube] x: Requested format is not available'), isTrue);
    expect(YtDlpService.isRetryable('ERROR: [youtube] x: Private video'), isFalse);
    expect(YtDlpService.isRetryable('ERROR: [youtube] x: Video unavailable. This video has been removed'), isFalse);
  });

  group('quality labels follow YouTube, not raw height', () {
    test('wide 2:1 video (e.g. Espresso)', () {
      expect(MediaFormat.qualityClass(3840, 1920), 2160);
      expect(MediaFormat.qualityClass(1920, 960), 1080);
      expect(MediaFormat.qualityClass(1280, 640), 720);
      expect(MediaFormat.qualityClass(854, 428), 480);
    });
    test('normal 16:9 and vertical Shorts', () {
      expect(MediaFormat.qualityClass(1920, 1080), 1080);
      expect(MediaFormat.qualityClass(1080, 1920), 1080);
      expect(MediaFormat.qualityClass(720, 1280), 720);
      expect(MediaFormat.qualityClass(null, 720), 720);
    });
    test('wide video options: labels by class, selectors by real height', () {
      final info = YtInfo.fromJson({
        'id': 'eVli-tstM5E',
        'title': 'Espresso',
        'formats': [
          {'format_id': '140', 'ext': 'm4a', 'vcodec': 'none', 'acodec': 'mp4a.40.2', 'abr': 129.0, 'filesize': 3000000},
          {'format_id': '137', 'ext': 'mp4', 'vcodec': 'avc1.640028', 'acodec': 'none', 'width': 1920, 'height': 960, 'filesize': 40000000},
          {'format_id': '313', 'ext': 'webm', 'vcodec': 'vp9', 'acodec': 'none', 'width': 3840, 'height': 1920, 'filesize': 200000000},
        ],
      });
      final v = MediaFormat.videoOptions(info);
      expect(v.map((f) => f.label), ['2160p', '1080p']);
      expect(v[0].selector, startsWith('bv*[height<=1920]'));
      expect(v[1].selector, startsWith('bv*[height<=960]'));
      expect(v[1].isHd, isTrue);
    });
  });
}
