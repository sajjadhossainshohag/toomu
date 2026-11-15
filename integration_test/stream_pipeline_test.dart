// End-to-end check of the iOS stream pipeline on a real device: manifest ->
// pieces -> mux -> AVFoundation finish -> every frame and audio sample
// decoded by AVAssetReader. Run on a connected iPhone from a Mac:
//
//   flutter test integration_test/stream_pipeline_test.dart -d <iphone-id>
//
// Add your own stream with --dart-define=STREAM_URL=https://.../master.m3u8
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:toomu/app/services/stream_downloader.dart';

const _native = MethodChannel('toomu/media_merge');
const _extra = String.fromEnvironment('STREAM_URL');

typedef _Case = ({String name, String url, int maxHeight, bool audio});

const _cases = <_Case>[
  (
    name: 'HLS fMP4, separate audio rendition (Apple)',
    url: 'https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8',
    maxHeight: 240,
    audio: true,
  ),
  (
    name: 'HLS MPEG-TS, separate audio rendition (Apple)',
    url: 'https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8',
    maxHeight: 240,
    audio: true,
  ),
  (
    name: 'HLS MPEG-TS, muxed audio (Mux)',
    url: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
    maxHeight: 360,
    audio: true,
  ),
  (
    name: 'HLS AES-128 (JW Player)',
    url: 'https://playertest.longtailvideo.com/adaptive/oceans_aes/oceans_aes.m3u8',
    maxHeight: 360,
    audio: true,
  ),
  (
    name: 'DASH SegmentTemplate \$Number\$ (Akamai)',
    url: 'https://dash.akamaized.net/akamai/bbb_30fps/bbb_30fps.mpd',
    maxHeight: 240,
    audio: true,
  ),
  (
    name: 'DASH multi-period (DASH-IF)',
    url: 'https://dash.akamaized.net/dash264/TestCases/5a/nomor/1.mpd',
    maxHeight: 720,
    audio: true,
  ),
  (
    name: 'DASH SegmentBase single files (DASH-IF)',
    url: 'https://dash.akamaized.net/dash264/TestCases/1a/netflix/exMPD_BIP_TC1.mpd',
    maxHeight: 0,
    audio: true,
  ),
  (
    name: 'DASH with VP9/Opus and H.264/AAC in MP4 (Shaka)',
    url: 'https://storage.googleapis.com/shaka-demo-assets/angel-one/dash.mpd',
    maxHeight: 480,
    audio: true,
  ),
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final cases = [
    ..._cases,
    if (_extra.isNotEmpty) (name: 'STREAM_URL', url: _extra, maxHeight: 720, audio: true),
  ];
  for (final c in cases) {
    testWidgets(c.name, (tester) async {
      final tmp = await getTemporaryDirectory();
      final work = '${tmp.path}/stream-test-${c.name.hashCode.toUnsigned(32)}';
      final path = await StreamDownloader(dio: Dio(), native: _native).download(
        url: c.url,
        headers: const {},
        work: work,
        maxHeight: c.maxHeight,
      );
      final info = Map<String, dynamic>.from(
        await _native.invokeMethod<Map<Object?, Object?>>('probe', {'path': path, 'decode': true}) ?? {},
      );
      debugPrint('[stream-test] ${c.name}\n  $path\n  $info');

      expect(info['playable'], isTrue, reason: 'AVFoundation must report the file playable');
      final tracks = [for (final t in info['tracks'] as List) Map<String, dynamic>.from(t as Map)];
      final video = tracks.where((t) => t['type'] == 'vide').toList();
      final audio = tracks.where((t) => t['type'] == 'soun').toList();
      expect(video, isNotEmpty, reason: 'no video track');
      expect(video.first['readerCompleted'], isTrue, reason: 'video decode: ${video.first['readerError']}');
      expect(video.first['decoded'] as int, greaterThan(0));
      if (c.audio) {
        expect(audio, isNotEmpty, reason: 'no audio track');
        expect(audio.first['readerCompleted'], isTrue, reason: 'audio decode: ${audio.first['readerError']}');
        expect(audio.first['decoded'] as int, greaterThan(0));
        final gap = ((video.first['seconds'] as num) - (audio.first['seconds'] as num)).abs();
        expect(gap, lessThan(1.0), reason: 'video and audio lengths differ by ${gap}s');
      }
    }, timeout: const Timeout(Duration(minutes: 20)));
  }
}
