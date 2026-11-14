import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/data/models/yt_info.dart';

const _ua = {'User-Agent': 'visionOS'};

const _info = YtInfo(
  id: 'abc123',
  title: '',
  uploader: '',
  duration: Duration(seconds: 213, milliseconds: 500),
  formats: [
    YtFormat(
      formatId: '137',
      ext: 'mp4',
      vcodec: 'avc1.640028',
      acodec: 'none',
      width: 1920,
      height: 1080,
      fps: 30,
      tbr: 4200,
      filesize: 80000000,
      url: 'https://rr1.googlevideo.com/videoplayback?itag=137&clen=80000000',
      httpHeaders: _ua,
    ),
    YtFormat(
      formatId: '140',
      ext: 'm4a',
      vcodec: 'none',
      acodec: 'mp4a.40.2',
      abr: 129.5,
      tbr: 129.5,
      filesize: 3400000,
      languagePreference: 10,
      url: 'https://rr1.googlevideo.com/videoplayback?itag=140&clen=3400000',
      httpHeaders: _ua,
    ),
    YtFormat(
      formatId: '251',
      ext: 'webm',
      vcodec: 'none',
      acodec: 'opus',
      abr: 140,
      filesize: 3500000,
      url: 'https://rr1.googlevideo.com/videoplayback?itag=251&clen=3500000&drc=1',
    ),
    YtFormat(
      formatId: 'hls-1080',
      ext: 'mp4',
      vcodec: 'avc1',
      acodec: 'mp4a',
      url: 'https://manifest.googlevideo.com/x.m3u8',
      protocol: 'm3u8_native',
    ),
  ],
);

void main() {
  final json = _info.toYtDlpInfo(title: 'My Song', uploader: 'Artist');

  test('has what yt-dlp needs to process a saved video result', () {
    expect(json['id'], 'abc123');
    expect(json['_type'], 'video');
    expect(json['title'], 'My Song');
    expect(json['uploader'], 'Artist');
    expect(json['extractor_key'], 'Youtube');
    expect(json['webpage_url'], 'https://www.youtube.com/watch?v=abc123');
    expect(json['duration'], 213.5);
    expect(json['thumbnail'], 'https://i.ytimg.com/vi/abc123/hqdefault.jpg');
    // Encodes cleanly (it's written to a file for --load-info-json).
    expect(() => jsonEncode(json), returnsNormally);
  });

  test('formats mirror yt-dlp\'s own YouTube format entries', () {
    final formats = (json['formats'] as List).cast<Map<String, Object?>>();
    expect(formats.map((f) => f['format_id']), ['137', '140', '251'], reason: 'manifest formats left out');
    final video = formats[0];
    expect(video['protocol'], 'https');
    expect(video['vcodec'], 'avc1.640028');
    expect(video['acodec'], 'none');
    expect(video['height'], 1080);
    expect(video['tbr'], 4200);
    expect(video['container'], 'mp4_dash');
    expect(video['http_headers'], _ua);
    final audio = formats[1];
    expect(audio['vcodec'], 'none');
    expect(audio['language_preference'], 10);
    expect(audio['container'], 'm4a_dash');
    expect(audio.containsKey('source_preference'), isFalse);
    expect(formats[2]['source_preference'], -2, reason: 'compressed-audio copy ranks lower');
  });
}
