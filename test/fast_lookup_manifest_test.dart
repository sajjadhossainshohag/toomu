import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:toomu/app/data/providers/youtube_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

const _id = 'abcdefghijk';
const _file = 'https://rr1---sn-x.googlevideo.com/videoplayback?itag=18&clen=1000';
const _dash = 'https://manifest.googlevideo.com/api/manifest/dash/id/$_id';

/// A live (or just-ended live) video: YouTube adds a DASH manifest next to the files.
Map<String, Object> _player() => {
  'playabilityStatus': {'status': 'OK'},
  'videoDetails': {'videoId': _id, 'title': 'Live news', 'lengthSeconds': '600'},
  'streamingData': {
    'formats': [
      {
        'itag': 18,
        'url': _file,
        'mimeType': 'video/mp4; codecs="avc1.42001E, mp4a.40.2"',
        'bitrate': 500000,
        'width': 640,
        'height': 360,
        'fps': 30,
        'contentLength': '1000',
        'qualityLabel': '360p',
      },
    ],
    'dashManifestUrl': _dash,
  },
};

const _mpd = '''<?xml version="1.0" encoding="UTF-8"?>
<MPD xmlns="urn:mpeg:dash:schema:mpd:2011"><Period><AdaptationSet mimeType="video/mp4">
<Representation id="137" codecs="avc1.640028" width="1920" height="1080" frameRate="30" bandwidth="4000000">
<BaseURL>https://rr1---sn-x.googlevideo.com/videoplayback/itag/137/clen/5000/</BaseURL>
</Representation></AdaptationSet></Period></MPD>''';

void main() {
  test('a live or just-ended live video does not break the fast lookup (Null check operator)', () async {
    // youtube_explode reads every DASH stream's bitrate with `!`, and its DASH parser never sets one: any
    // player answer with a DASH manifest failed with "Null check operator used on a null value".
    final asked = <String>[];
    final mock = MockClient((req) async {
      asked.add('${req.method} ${req.url}');
      if (req.url.path.endsWith('/youtubei/v1/player')) return http.Response(jsonEncode(_player()), 200, request: req);
      if (req.url.toString().startsWith(_dash)) return http.Response(_mpd, 200, request: req);
      return http.Response('', 200, headers: {'content-length': '1000'}, request: req);
    });
    final provider = YoutubeProvider(http: YoutubeHttp(mock));
    addTearDown(provider.dispose);

    final manifest = await provider.manifestFor(_id, YoutubeApiClient.androidSdkless);

    expect([for (final s in manifest.streams) s.tag], [18]);
    expect(asked.where((a) => a.contains('manifest/dash')), isEmpty, reason: 'Toomu plays files, not DASH');
  });
}
