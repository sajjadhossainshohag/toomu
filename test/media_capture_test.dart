import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/core/utils/media_manifest.dart';
import 'package:toomu/app/data/models/captured_media.dart';
import 'package:toomu/app/data/models/download_task.dart';
import 'package:toomu/app/modules/browser/media_capture.dart';

void main() {
  group('HLS', () {
    final base = Uri.parse('https://cdn.example.com/v/abc/master.m3u8?token=1');

    test('master playlist: one quality per height, best first, links resolved', () {
      const master = '''
#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",NAME="en",URI="audio/en.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360,CODECS="avc1.4d401e,mp4a.40.2",AUDIO="a"
360/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2500000,RESOLUTION=1280x720,CODECS="avc1.4d401f,mp4a.40.2",AUDIO="a"
720/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2100000,RESOLUTION=1280x720,CODECS="avc1.4d401f,mp4a.40.2",AUDIO="a"
720b/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=64000,CODECS="mp4a.40.2"
audio-only.m3u8
''';
      final info = MediaManifest.parseHls(master, base);
      expect(info.variants.map((v) => v.height), [720, 360]);
      expect(info.variants.first.bandwidth, 2500000);
      expect(info.variants.first.url, 'https://cdn.example.com/v/abc/720/index.m3u8');
      expect(info.renditions.map((r) => r.url), ['https://cdn.example.com/v/abc/audio/en.m3u8']);
      expect(info.variants.first.audioGroup, 'a');
      expect(info.audioOnly, isFalse);
      expect(info.protected, isFalse);
    });

    test('media playlist: duration from EXTINF, AES-128 is not DRM', () {
      const media = '''
#EXTM3U
#EXT-X-TARGETDURATION:6
#EXT-X-KEY:METHOD=AES-128,URI="key.bin"
#EXTINF:6.0,
seg0.ts
#EXTINF:6.0,
seg1.ts
#EXTINF:3.5,
seg2.ts
#EXT-X-ENDLIST
''';
      final info = MediaManifest.parseHls(media, base);
      expect(info.duration, const Duration(milliseconds: 15500));
      expect(info.variants, isEmpty);
      expect(info.protected, isFalse);
    });

    test('FairPlay / SAMPLE-AES is protected', () {
      const drm = '''
#EXTM3U
#EXT-X-KEY:METHOD=SAMPLE-AES,URI="skd://x",KEYFORMAT="com.apple.streamingkeydelivery"
#EXTINF:6.0,
seg0.ts
''';
      expect(MediaManifest.parseHls(drm, base).protected, isTrue);
    });

    test('audio-only master', () {
      const master = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=128000,CODECS="mp4a.40.2"
hi.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=64000,CODECS="mp4a.40.5"
lo.m3u8
''';
      final info = MediaManifest.parseHls(master, base);
      expect(info.audioOnly, isTrue);
      expect(info.variants.first.bandwidth, 128000);
    });
  });

  group('DASH', () {
    test('video qualities, duration, DRM flag', () {
      const mpd = '''
<MPD mediaPresentationDuration="PT1M30.5S">
  <Period>
    <AdaptationSet mimeType="video/mp4">
      <Representation id="1" bandwidth="1000000" width="854" height="480" codecs="avc1"/>
      <Representation id="2" bandwidth="3000000" width="1920" height="1080" codecs="avc1"/>
    </AdaptationSet>
    <AdaptationSet mimeType="audio/mp4">
      <Representation id="3" bandwidth="128000" codecs="mp4a.40.2"/>
    </AdaptationSet>
  </Period>
</MPD>''';
      final info = MediaManifest.parseDash(mpd, 'https://x.com/a.mpd');
      expect(info.variants.map((v) => v.height), [1080, 480]);
      expect(info.duration, const Duration(milliseconds: 90500));
      expect(info.protected, isFalse);
      expect(info.audioOnly, isFalse);
      expect(MediaManifest.parseDash('<MPD><ContentProtection/></MPD>', '').protected, isTrue);
    });

    test('ISO 8601 durations', () {
      expect(MediaManifest.isoDuration('PT1H2M3S'), const Duration(hours: 1, minutes: 2, seconds: 3));
      expect(MediaManifest.isoDuration('PT45.25S'), const Duration(milliseconds: 45250));
      expect(MediaManifest.isoDuration('nonsense'), isNull);
    });
  });

  group('noise and matching', () {
    test('numbered pieces are segments, a quality ladder is not', () {
      final segments = [for (var i = 1; i <= 5; i++) 'https://c.com/v/seg-$i.mp4'];
      expect(MediaManifest.looksLikeSegments(segments), isTrue);
      final ladder = [for (final h in [1080, 720, 480, 360]) 'https://v.redd.it/x/DASH_$h.mp4'];
      expect(MediaManifest.looksLikeSegments(ladder), isFalse);
      expect(MediaManifest.looksLikeSegments(segments.take(3).toList()), isFalse);
      expect(MediaManifest.segmentKey(segments[0]), MediaManifest.segmentKey(segments[4]));
    });

    test('a refreshed link matches by path, file name or large size', () {
      expect(
        MediaManifest.sameMedia('https://a.com/v/movie.mp4?exp=1', 0, 'https://a.com/v/movie.mp4?exp=2', 0),
        isTrue,
      );
      expect(
        MediaManifest.sameMedia('https://a.com/v/movie.mp4', 0, 'https://cdn2.a.com/x/movie.mp4', 0),
        isTrue,
      );
      expect(MediaManifest.sameMedia('https://a.com/1', 50 << 20, 'https://b.com/2', 50 << 20), isTrue);
      expect(MediaManifest.sameMedia('https://a.com/1', 1000, 'https://b.com/2', 1000), isFalse);
      expect(MediaManifest.sameMedia('https://a.com/a.mp4', 0, 'https://a.com/b.mp4', 0), isFalse);
    });
  });

  group('saved downloads', () {
    test('headers and page survive a save; unknown status does not throw', () {
      final t = DownloadTask(
        id: '1',
        title: 't',
        kind: DownloadKind.video,
        extension: 'mp4',
        filePath: '/x.mp4',
        createdAt: DateTime(2026),
        source: DownloadSource.stream,
        url: 'https://a.com/master.m3u8',
        pageUrl: 'https://a.com/watch',
        headers: const {'User-Agent': 'UA', 'Referer': 'https://a.com/watch'},
      );
      final json = t.toJson();
      final back = DownloadTask.fromJson(json);
      expect(back.source, DownloadSource.stream);
      expect(back.pageUrl, 'https://a.com/watch');
      expect(back.headers, {'User-Agent': 'UA', 'Referer': 'https://a.com/watch'});

      final odd = DownloadTask.fromJson({...json, 'status': 'someFutureState', 'headers': null});
      expect(odd.status.value, DownloadStatus.paused);
      expect(odd.headers, isEmpty);
      expect(odd.subtitles, isEmpty);
    });

    test('subtitle links from the page survive a save', () {
      final t = DownloadTask(
        id: '1',
        title: 't',
        kind: DownloadKind.video,
        extension: 'mp4',
        filePath: '/x.mp4',
        createdAt: DateTime(2026),
        source: DownloadSource.direct,
        subtitles: const {'en': 'https://a.com/en.vtt'},
      );
      expect(DownloadTask.fromJson(t.toJson()).subtitles, {'en': 'https://a.com/en.vtt'});
    });
  });

  group('own subtitles', () {
    test('HLS master with a subtitle track', () {
      const master = '''
#EXTM3U
#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",LANGUAGE="en",NAME="English",URI="subs/en.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360,SUBTITLES="subs"
360/index.m3u8
''';
      expect(MediaManifest.hasSubtitles(master), isTrue);
    });

    test('HLS with only audio tracks, or closed captions inside the video, has none to fetch', () {
      const master = '''
#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",NAME="en",URI="audio/en.m3u8"
#EXT-X-MEDIA:TYPE=CLOSED-CAPTIONS,GROUP-ID="cc",NAME="CC1",INSTREAM-ID="CC1"
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360,AUDIO="a",CLOSED-CAPTIONS="cc"
360/index.m3u8
''';
      expect(MediaManifest.hasSubtitles(master), isFalse);
    });

    test('DASH text tracks in any of their spellings', () {
      for (final set in [
        '<AdaptationSet contentType="text" lang="en">',
        '<AdaptationSet mimeType="text/vtt" lang="en">',
        '<AdaptationSet mimeType="application/ttml+xml">',
        '<AdaptationSet mimeType="application/mp4" codecs="stpp">',
        '<AdaptationSet mimeType="application/mp4"><Representation codecs="wvtt"/>',
      ]) {
        expect(MediaManifest.hasSubtitles('<MPD><Period>$set</AdaptationSet></Period></MPD>'), isTrue, reason: set);
      }
      expect(
        MediaManifest.hasSubtitles('<MPD><AdaptationSet mimeType="video/mp4" codecs="avc1"/></MPD>'),
        isFalse,
      );
    });

    test('subtitle tracks of a video element are kept with the captured video', () {
      final media = CapturedMedia(
        url: 'https://a.com/v.mp4',
        type: CapturedType.file,
        kind: DownloadKind.video,
        pageUrl: 'https://a.com/watch',
        headers: const {},
      );
      MediaCapture.applyElement(media, {
        'subs': [
          {'url': 'https://a.com/en.vtt', 'lang': 'en', 'kind': 'subtitles'},
        ],
      });
      expect(media.subtitles, {'en': 'https://a.com/en.vtt'});
      MediaCapture.applyElement(media, {'subs': []});
      expect(media.subtitles, {'en': 'https://a.com/en.vtt'}, reason: 'a later scan without tracks keeps them');
    });
  });
}
