import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/data/models/youtube_stream.dart';
import 'package:toomu/app/data/models/yt_info.dart';
import 'package:toomu/app/services/video_session_service.dart';

YtFormat _v(String id, String codec, int w, int h, {double fps = 30, String protocol = 'https'}) => YtFormat(
    formatId: id, ext: 'mp4', vcodec: codec, acodec: 'none', width: w, height: h, fps: fps,
    url: 'https://v/$id', protocol: protocol);

const _audio = YtFormat(
    formatId: '140', ext: 'm4a', vcodec: 'none', acodec: 'mp4a.40.2', abr: 129, url: 'https://a/140', protocol: 'https');
const _combined = YtFormat(
    formatId: '18', ext: 'mp4', vcodec: 'avc1.42001E', acodec: 'mp4a.40.2', width: 640, height: 360,
    url: 'https://c/18', protocol: 'https');

YtInfo _info(List<YtFormat> formats) => YtInfo(id: 'abc', title: 'T', uploader: 'U', formats: formats);

void main() {
  test('best H.264 up to 1080p + separate audio, combined stream as fallback', () {
    final item = YoutubeStream.pick(
      _info([
        _v('137', 'avc1.640028', 1920, 1080),
        _v('248', 'vp9', 1920, 1080),
        _v('399', 'av01.0.08M.08', 1920, 1080),
        _v('313', 'vp9', 3840, 2160), // above the cap
        _audio,
        _combined,
      ]),
      videoId: 'abc',
    )!;
    expect(item.uri, 'https://v/137');
    expect(item.audioUri, 'https://a/140');
    expect(item.resumeKey, 'yt:abc');
    expect(item.fallback?.uri, 'https://c/18');
    expect(item.fallback?.audioUri, isNull);
  });

  test('vertical Shorts are capped by their width', () {
    final item = YoutubeStream.pick(
      _info([_v('a', 'avc1', 1080, 1920), _v('b', 'avc1', 2160, 3840), _audio]),
      videoId: 'abc',
    )!;
    expect(item.uri, 'https://v/a');
    expect(item.isLandscape, isFalse);
  });

  test('AV1 only when nothing hardware-friendly exists', () {
    final item = YoutubeStream.pick(_info([_v('399', 'av01', 1920, 1080), _audio]), videoId: 'abc')!;
    expect(item.uri, 'https://v/399');
  });

  test('manifests are skipped; combined stream when no separate one works', () {
    final item = YoutubeStream.pick(
      _info([_v('hls', 'avc1', 1920, 1080, protocol: 'm3u8_native'), _audio, _combined]),
      videoId: 'abc',
    )!;
    expect(item.uri, 'https://c/18');
    expect(item.audioUri, isNull);
  });

  test('nothing playable → null', () {
    expect(YoutubeStream.pick(_info([_audio]), videoId: 'abc'), isNull);
  });

  test('quality list: one per quality, best codec, frame rate in the label', () {
    final list = YoutubeStream.qualities(_info([
      _v('401', 'av01', 3840, 2160),
      _v('299', 'avc1', 1920, 1080, fps: 60),
      _v('248', 'vp9', 1920, 1080),
      _v('136', 'avc1', 1280, 720),
      _audio,
    ]));
    expect(list.map((q) => q.label), ['4K', '1080p60', '720p']);
    expect(list[1].codec, 'H.264');
    expect(list.every((q) => q.audioUri == 'https://a/140'), isTrue);
  });

  test('remembered choice picks the highest quality at or below it', () {
    final info = _info([_v('299', 'avc1', 1920, 1080), _v('136', 'avc1', 1280, 720), _v('135', 'avc1', 854, 480), _audio]);
    final item = YoutubeStream.pick(info, videoId: 'abc', preferred: 720)!;
    expect(item.currentQuality?.label, '720p');
    expect(YoutubeStream.pick(info, videoId: 'abc', preferred: 144)!.currentQuality?.label, '480p');
  });

  test('switching quality keeps the list, title and fallback', () {
    final item = YoutubeStream.pick(
      _info([_v('299', 'avc1', 1920, 1080), _v('136', 'avc1', 1280, 720), _audio, _combined]),
      videoId: 'abc',
      title: 'Song',
    )!;
    final lower = item.withQuality(item.qualities.last);
    expect(lower.uri, 'https://v/136');
    expect(lower.title, 'Song');
    expect(lower.qualities, hasLength(2));
    expect(lower.fallback?.uri, 'https://c/18');
    expect(lower.fallback?.qualities, hasLength(2)); // menu still works after falling back
  });

  test('EDL joins video + audio; URL lengths make ; and , safe', () {
    const v = 'https://v/1?a=1;b=2,c';
    const a = 'https://a/2?x=%3B';
    const head = '!new_stream;!no_clip;!no_chapters;';
    expect(VideoSessionService.edl(v, a), 'edl://$head%${v.length}%$v;$head%${a.length}%$a');
  });

  test('fast-lookup streams are marked provisional, and stay so across qualities', () {
    final item = YoutubeStream.pick(
      _info([_v('299', 'avc1', 1920, 1080), _v('136', 'avc1', 1280, 720), _audio, _combined]),
      videoId: 'abc',
      provisional: true,
      partial: true,
    )!;
    expect(item.provisional, isTrue);
    expect(item.partial, isTrue);
    expect(item.youtubeId, 'abc');
    expect(item.withQuality(item.qualities.last).provisional, isTrue);
    expect(item.withQuality(item.qualities.last).partial, isTrue);
    expect(item.fallback?.provisional, isTrue);
    expect(item.fallback?.partial, isTrue);
  });
}
