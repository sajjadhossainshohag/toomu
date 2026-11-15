import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/core/utils/media_manifest.dart';
import 'package:toomu/app/core/utils/stream_plan.dart';

void main() {
  final base = Uri.parse('https://cdn.example.com/hls/v/index.m3u8');

  group('HLS media playlist', () {
    test('init section, byte ranges, AES-128 keys and IVs', () {
      const text = '''
#EXTM3U
#EXT-X-VERSION:7
#EXT-X-MEDIA-SEQUENCE:5
#EXT-X-MAP:URI="init.mp4",BYTERANGE="720@0"
#EXT-X-KEY:METHOD=AES-128,URI="https://k.example.com/key"
#EXTINF:4.0,
#EXT-X-BYTERANGE:1000@720
media.mp4
#EXTINF:4.0,
#EXT-X-BYTERANGE:2000
media.mp4
#EXT-X-KEY:METHOD=AES-128,URI="key2",IV=0x000102030405060708090A0B0C0D0E0F
#EXTINF:4.0,
seg3.m4s
#EXT-X-KEY:METHOD=NONE
#EXTINF:4.0,
seg4.m4s
#EXT-X-ENDLIST
''';
      final run = StreamPlanner.hlsMedia(text, base).runs.single;
      expect(run.container, TrackContainer.fmp4);
      expect(run.init!.url, 'https://cdn.example.com/hls/v/init.mp4');
      expect(run.init!.range, 'bytes=0-719');
      expect(run.init!.keyUrl, isNull);
      expect(run.parts.length, 5);

      final s = run.segments;
      expect(s[0].range, 'bytes=720-1719');
      expect(s[1].range, 'bytes=1720-3719');
      expect(s[0].keyUrl, 'https://k.example.com/key');
      expect(s[0].iv, [for (var i = 0; i < 15; i++) 0, 5]);
      expect(s[1].iv!.last, 6);
      expect(s[2].keyUrl, 'https://cdn.example.com/hls/v/key2');
      expect(s[2].iv, List.generate(16, (i) => i));
      expect(s[3].keyUrl, isNull);
      expect(s[3].range, isNull);
    });

    test('discontinuities and init changes start new runs, order kept', () {
      const text = '''
#EXTM3U
#EXT-X-MAP:URI="a/init.mp4"
#EXTINF:4,
a/1.m4s
#EXTINF:4,
a/2.m4s
#EXT-X-DISCONTINUITY
#EXT-X-MAP:URI="ad/init.mp4"
#EXTINF:4,
ad/1.m4s
#EXT-X-DISCONTINUITY
#EXT-X-MAP:URI="a/init.mp4"
#EXTINF:4,
a/3.m4s
#EXT-X-ENDLIST
''';
      final runs = StreamPlanner.hlsMedia(text, base).runs;
      expect(runs.length, 3);
      expect(runs.map((r) => r.init!.url.split('/hls/v/').last), ['a/init.mp4', 'ad/init.mp4', 'a/init.mp4']);
      expect(runs.expand((r) => r.segments).map((s) => s.url.split('/hls/v/').last), [
        'a/1.m4s',
        'a/2.m4s',
        'ad/1.m4s',
        'a/3.m4s',
      ]);
    });

    test('an init section after a key with an IV is decrypted with it', () {
      const text = '''
#EXTM3U
#EXT-X-KEY:METHOD=AES-128,URI="k",IV=0x00000000000000000000000000000009
#EXT-X-MAP:URI="init.mp4"
#EXTINF:4,
1.m4s
#EXT-X-ENDLIST
''';
      final init = StreamPlanner.hlsMedia(text, base).runs.single.init!;
      expect(init.keyUrl, 'https://cdn.example.com/hls/v/k');
      expect(init.iv!.last, 9);
    });

    test('TS pieces, live streams and DRM', () {
      const ts = '#EXTM3U\n#EXTINF:6,\na.ts\n#EXTINF:6,\nb.ts\n#EXT-X-ENDLIST\n';
      final run = StreamPlanner.hlsMedia(ts, base).runs.single;
      expect(run.container, TrackContainer.ts);
      expect(run.extension, 'ts');
      expect(run.parts.map((p) => p.url), [
        'https://cdn.example.com/hls/v/a.ts',
        'https://cdn.example.com/hls/v/b.ts',
      ]);

      expect(
        () => StreamPlanner.hlsMedia('#EXTM3U\n#EXTINF:6,\na.ts\n', base),
        throwsA(StreamPlanner.live),
      );
      expect(
        () => StreamPlanner.hlsMedia(
          '#EXTM3U\n#EXT-X-KEY:METHOD=SAMPLE-AES,URI="skd://k"\n#EXTINF:6,\na.ts\n#EXT-X-ENDLIST\n',
          base,
        ),
        throwsA(StreamPlanner.drm),
      );
    });

    test('quality and audio track choice', () {
      const master = '''
#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aac",NAME="es",URI="es.m3u8"
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aac",NAME="en",DEFAULT=YES,URI="en.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080,AUDIO="aac"
1080.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2500000,RESOLUTION=1280x720,AUDIO="aac"
720.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360,AUDIO="aac"
360.m3u8
''';
      final info = MediaManifest.parseHls(master, base);
      expect(StreamPlanner.pickVariant(info.variants, 720).height, 720);
      expect(StreamPlanner.pickVariant(info.variants, 0).height, 1080);
      expect(StreamPlanner.pickVariant(info.variants, 240).height, 360);
      final audio = StreamPlanner.audioFor(info.variants.first, info.renditions);
      expect(audio!.url, 'https://cdn.example.com/hls/v/en.m3u8');
    });
  });

  group('DASH', () {
    final mpdUrl = Uri.parse('https://x.com/m/manifest.mpd');

    const templated = '''
<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" type="static" mediaPresentationDuration="PT10S">
  <BaseURL>https://cdn.example.com/dash/</BaseURL>
  <Period>
    <AdaptationSet mimeType="video/mp4" contentType="video">
      <SegmentTemplate timescale="1000" duration="4000" startNumber="1"
          media="\$RepresentationID\$/seg-\$Number%05d\$.m4s" initialization="\$RepresentationID\$/init.mp4"/>
      <Representation id="v1080" bandwidth="5000000" width="1920" height="1080" codecs="avc1.640028"/>
      <Representation id="v720" bandwidth="2500000" width="1280" height="720" codecs="avc1.64001f"/>
      <Representation id="v720vp9" bandwidth="2000000" width="1280" height="720" codecs="vp09.00.31.08"/>
    </AdaptationSet>
    <AdaptationSet mimeType="video/webm" contentType="video">
      <Representation id="webm" bandwidth="1" width="3840" height="2160" codecs="vp9"/>
    </AdaptationSet>
    <AdaptationSet mimeType="audio/mp4" contentType="audio">
      <SegmentTemplate timescale="48000" media="a/\$Number\$.m4s" initialization="a/init.mp4">
        <SegmentTimeline><S t="0" d="96000" r="2"/><S d="48000"/></SegmentTimeline>
      </SegmentTemplate>
      <Representation id="a1" bandwidth="128000" codecs="mp4a.40.2"/>
    </AdaptationSet>
  </Period>
</MPD>''';

    test('number template, timeline, quality cap, H.264 preferred, WebM skipped', () {
      final plan = StreamPlanner.dash(templated, mpdUrl, maxHeight: 720);
      final v = plan.video!.runs.single;
      expect(v.init!.url, 'https://cdn.example.com/dash/v720/init.mp4');
      expect(v.segments.map((s) => s.url), [
        'https://cdn.example.com/dash/v720/seg-00001.m4s',
        'https://cdn.example.com/dash/v720/seg-00002.m4s',
        'https://cdn.example.com/dash/v720/seg-00003.m4s',
      ]);
      final a = plan.audio!.runs.single;
      expect(a.init!.url, 'https://cdn.example.com/dash/a/init.mp4');
      expect(a.segments.map((s) => s.url.split('/').last), ['1.m4s', '2.m4s', '3.m4s', '4.m4s']);

      expect(StreamPlanner.dash(templated, mpdUrl).video!.runs.single.init!.url, contains('v1080'));
      expect(StreamPlanner.dash(templated, mpdUrl, audioOnly: true).video, isNull);
    });

    test('VP9 and AV1 in MP4 are accepted, not refused', () {
      const mpd = '''
<MPD mediaPresentationDuration="PT4S"><Period>
  <AdaptationSet mimeType="video/mp4">
    <SegmentTemplate timescale="1" duration="2" media="v/\$Number\$.m4s" initialization="v/init.mp4"/>
    <Representation id="av1" bandwidth="1" height="1080" codecs="av01.0.08M.08"/>
  </AdaptationSet>
  <AdaptationSet mimeType="audio/mp4">
    <SegmentTemplate timescale="1" duration="2" media="a/\$Number\$.m4s" initialization="a/init.mp4"/>
    <Representation id="opus" bandwidth="1" codecs="opus"/>
  </AdaptationSet>
</Period></MPD>''';
      final plan = StreamPlanner.dash(mpd, mpdUrl);
      expect(plan.video!.runs.single.segments.length, 2);
      expect(plan.audio!.runs.single.init!.url, 'https://x.com/m/a/init.mp4');
    });

    test('several periods become runs, with BaseURL and period timing', () {
      const mpd = '''
<MPD mediaPresentationDuration="PT10S">
  <BaseURL>https://cdn.example.com/</BaseURL>
  <Period id="p1" start="PT0S">
    <BaseURL>p1/</BaseURL>
    <AdaptationSet mimeType="video/mp4">
      <SegmentTemplate timescale="1" duration="2" media="\$Number\$.m4s" initialization="init.mp4"/>
      <Representation id="v" bandwidth="1" height="360" codecs="avc1"/>
    </AdaptationSet>
  </Period>
  <Period id="p2" start="PT4S">
    <BaseURL>p2/</BaseURL>
    <AdaptationSet mimeType="video/mp4">
      <SegmentTemplate timescale="1" duration="2" media="\$Number\$.m4s" initialization="init.mp4"/>
      <Representation id="v" bandwidth="1" height="360" codecs="avc1"/>
    </AdaptationSet>
  </Period>
</MPD>''';
      final runs = StreamPlanner.dash(mpd, mpdUrl).video!.runs;
      expect(runs.length, 2);
      expect(runs[0].init!.url, 'https://cdn.example.com/p1/init.mp4');
      expect(runs[0].segments.length, 2); // 4 s period
      expect(runs[1].init!.url, 'https://cdn.example.com/p2/init.mp4');
      expect(runs[1].segments.length, 3); // remaining 6 s
    });

    test('segment list with ranges, single-file representation', () {
      const mpd = '''
<MPD mediaPresentationDuration="PT8S"><Period>
  <AdaptationSet mimeType="video/mp4">
    <Representation id="1" bandwidth="1" height="480" codecs="avc1">
      <BaseURL>v.mp4</BaseURL>
      <SegmentList>
        <Initialization sourceURL="v.mp4" range="0-99"/>
        <SegmentURL media="v.mp4" mediaRange="100-199"/>
      </SegmentList>
    </Representation>
  </AdaptationSet>
  <AdaptationSet mimeType="audio/mp4">
    <Representation id="2" bandwidth="1" codecs="mp4a.40.2">
      <BaseURL>https://x.com/a.mp4</BaseURL>
      <SegmentBase indexRange="0-10"/>
    </Representation>
  </AdaptationSet>
</Period></MPD>''';
      final plan = StreamPlanner.dash(mpd, mpdUrl);
      final v = plan.video!.runs.single;
      expect(v.init!.url, 'https://x.com/m/v.mp4');
      expect(v.init!.range, 'bytes=0-99');
      expect(v.segments.single.range, 'bytes=100-199');
      final a = plan.audio!.runs.single;
      expect(a.segments.single.url, 'https://x.com/a.mp4');
      expect(a.init, isNull);
    });

    test('live, DRM and WebM-only streams get clear messages', () {
      expect(
        () => StreamPlanner.dash('<MPD type="dynamic"><Period/></MPD>', mpdUrl),
        throwsA(StreamPlanner.live),
      );
      expect(
        () => StreamPlanner.dash('<MPD><Period><ContentProtection/></Period></MPD>', mpdUrl),
        throwsA(StreamPlanner.drm),
      );
      expect(
        () => StreamPlanner.dash(
          '<MPD mediaPresentationDuration="PT4S"><Period><AdaptationSet mimeType="video/webm">'
          '<Representation id="1" height="720" codecs="vp9"/></AdaptationSet></Period></MPD>',
          mpdUrl,
        ),
        throwsA(StreamPlanner.webmOnly),
      );
    });
  });
}
