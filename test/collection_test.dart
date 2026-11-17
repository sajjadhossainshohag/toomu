import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/core/utils/link_parser.dart';
import 'package:toomu/app/data/models/download_task.dart';
import 'package:toomu/app/data/models/media_format.dart';
import 'package:toomu/app/data/models/video_meta.dart';
import 'package:toomu/app/data/models/yt_collection.dart';
import 'package:toomu/app/services/download_service.dart';

// Shape of `yt-dlp --flat-playlist -J` (yt-dlp 2026.10.26), trimmed from a real run.
const flatPlaylist = {
  '_type': 'playlist',
  'id': 'PL4cUxeGkcC9gcy9lrvMJ75z9maRw4byYp',
  'title': 'Node JS Tutorial for Beginners',
  'uploader': 'Net Ninja',
  'entries': [
    {
      '_type': 'url',
      'ie_key': 'Youtube',
      'id': 'w-7RQ46RgxU',
      'url': 'https://www.youtube.com/watch?v=w-7RQ46RgxU',
      'title': 'Node JS Tutorial for Beginners #1 - Introduction',
      'duration': 286,
    },
    {'_type': 'url', 'ie_key': 'Youtube', 'id': 'Ok1mU7CRtnU', 'title': '[Deleted video]', 'duration': null},
    {'_type': 'url', 'ie_key': 'Youtube', 'id': 'aBcDeFgHiJk', 'title': 'Live now', 'duration': null},
    {'_type': 'url', 'ie_key': 'Youtube', 'id': 'zXy_123-abc', 'title': 'Part 2', 'duration': 301.0},
    {'_type': 'url', 'ie_key': 'YoutubeTab', 'id': 'UCxxxxxxxxxxxxxxxxxxxxxx', 'title': 'A channel'},
  ],
};

const flatChannel = {
  '_type': 'playlist',
  'title': 'YouTube - Videos',
  'channel': 'YouTube',
  'uploader': 'YouTube',
  'entries': [
    {'_type': 'url', 'ie_key': 'Youtube', 'id': 'dD33lDxL9K0', 'title': 'Sketches for \$5', 'duration': 441},
  ],
};

void main() {
  group('playlist and channel links', () {
    const list = 'PL4cUxeGkcC9gcy9lrvMJ75z9maRw4byYp';
    const playlist = 'https://www.youtube.com/playlist?list=$list';

    test('a playlist link, also shared from the app or YouTube Music', () {
      expect(LinkParser.youtubeCollection(playlist), playlist);
      expect(LinkParser.youtubeCollection('https://youtube.com/playlist?list=$list&si=Ab12'), playlist);
      expect(LinkParser.youtubeCollection('https://m.youtube.com/playlist?list=$list'), playlist);
      expect(
        LinkParser.youtubeCollection('https://music.youtube.com/playlist?list=OLAK5uy_kwLEgHqU3S3SY'),
        'https://www.youtube.com/playlist?list=OLAK5uy_kwLEgHqU3S3SY',
      );
      expect(LinkParser.youtubeCollection('Look at this: $playlist&si=x, great course!'), playlist);
    });

    test('a channel link lists its videos', () {
      for (final link in [
        'https://www.youtube.com/@YouTube',
        'https://youtube.com/@YouTube?si=abc',
        'https://m.youtube.com/@YouTube/featured',
        'https://www.youtube.com/@YouTube/videos',
      ]) {
        expect(LinkParser.youtubeCollection(link), 'https://www.youtube.com/@YouTube/videos', reason: link);
      }
      expect(
        LinkParser.youtubeCollection('https://www.youtube.com/channel/UCBR8-60-B28hp2BmDPdntcQ/about'),
        'https://www.youtube.com/channel/UCBR8-60-B28hp2BmDPdntcQ/videos',
      );
      expect(LinkParser.youtubeCollection('https://www.youtube.com/user/YouTube'), 'https://www.youtube.com/user/YouTube/videos');
      expect(LinkParser.youtubeCollection('https://www.youtube.com/c/YouTube'), 'https://www.youtube.com/c/YouTube/videos');
    });

    test('a video link stays a single video, even inside a playlist', () {
      expect(LinkParser.youtubeCollection('https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=$list'), isNull);
      expect(LinkParser.youtubeCollection('https://youtu.be/dQw4w9WgXcQ?list=$list'), isNull);
      expect(LinkParser.youtubeCollection('https://www.youtube.com/shorts/dQw4w9WgXcQ'), isNull);
      expect(LinkParser.youtubeVideoId('https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=$list'), 'dQw4w9WgXcQ');
    });

    test('never-ending mixes, private lists and other sites are not playlists to download', () {
      expect(LinkParser.youtubeCollection('https://www.youtube.com/playlist?list=RDdQw4w9WgXcQ'), isNull);
      expect(LinkParser.youtubeCollection('https://www.youtube.com/playlist?list=WL'), isNull);
      expect(LinkParser.youtubeCollection('https://www.youtube.com/playlist?list=LL'), isNull);
      expect(LinkParser.youtubeCollection('https://example.com/playlist?list=$list'), isNull);
      expect(LinkParser.youtubeCollection('https://www.youtube.com/results?search_query=x'), isNull);
      expect(LinkParser.youtubeCollection('node js tutorial'), isNull);
    });

    test('a playlist or channel link is not mistaken for a video', () {
      expect(LinkParser.youtubeVideoId(playlist), isNull);
      expect(LinkParser.youtubeVideoId('https://www.youtube.com/@YouTube'), isNull);
    });
  });

  group('reading the list', () {
    test('only downloadable videos: deleted, private, live and non-video entries are left out', () {
      final c = YtCollection.fromFlatJson(flatPlaylist);
      expect(c.title, 'Node JS Tutorial for Beginners');
      expect(c.author, 'Net Ninja');
      expect(c.videos.map((v) => v.id), ['w-7RQ46RgxU', 'zXy_123-abc']);
      final first = c.videos.first;
      expect(first.title, 'Node JS Tutorial for Beginners #1 - Introduction');
      expect(first.author, 'Net Ninja');
      expect(first.duration, const Duration(seconds: 286));
      expect(first.thumbnailUrl, 'https://i.ytimg.com/vi/w-7RQ46RgxU/mqdefault.jpg');
    });

    test('a channel is named after the channel, not its tab', () {
      final c = YtCollection.fromFlatJson(flatChannel);
      expect(c.title, 'YouTube');
      expect(c.videos.single.author, 'YouTube');
    });

    test('an empty or odd answer gives an empty list instead of an error', () {
      expect(YtCollection.fromFlatJson(const {'_type': 'playlist'}).videos, isEmpty);
      expect(YtCollection.fromFlatJson(const {'entries': 'x'}).videos, isEmpty);
    });
  });

  group('queueing a whole list', () {
    VideoMeta video(String id) => VideoMeta(id: id, title: id, author: '', thumbnailUrl: '');
    DownloadTask task(String videoId, DownloadKind kind, DownloadStatus status) => DownloadTask(
          id: videoId,
          title: videoId,
          kind: kind,
          extension: 'mp4',
          filePath: '/x/$videoId.mp4',
          createdAt: DateTime(2026),
          videoId: videoId,
          status: status,
        );

    test('videos already in Downloads as the same kind are skipped', () {
      final existing = [
        task('aaaaaaaaaaa', DownloadKind.video, DownloadStatus.completed),
        task('bbbbbbbbbbb', DownloadKind.video, DownloadStatus.paused),
        task('ccccccccccc', DownloadKind.audio, DownloadStatus.completed),
      ];
      final fresh = DownloadService.notYetQueued(
        [video('aaaaaaaaaaa'), video('bbbbbbbbbbb'), video('ccccccccccc'), video('ddddddddddd')],
        existing,
        DownloadKind.video,
      );
      expect(fresh.map((v) => v.id), ['ccccccccccc', 'ddddddddddd']);
    });

    test('a canceled download is queued again', () {
      final fresh = DownloadService.notYetQueued(
        [video('aaaaaaaaaaa')],
        [task('aaaaaaaaaaa', DownloadKind.video, DownloadStatus.canceled)],
        DownloadKind.video,
      );
      expect(fresh, hasLength(1));
    });

    test('the same video twice in one list is queued once', () {
      final fresh = DownloadService.notYetQueued([video('aaaaaaaaaaa'), video('aaaaaaaaaaa')], const [], DownloadKind.video);
      expect(fresh, hasLength(1));
    });
  });

  group('one quality for the whole list', () {
    test('video choices use the same yt-dlp selectors as a single video', () {
      final options = MediaFormat.listOptions();
      final p720 = options.firstWhere((f) => f.label == '720p');
      expect(p720.kind, DownloadKind.video);
      expect(p720.extension, 'mp4');
      expect(p720.height, 720);
      expect(p720.selector, 'bv*[height<=720][vcodec^=avc1]+ba[ext=m4a]/bv*[height<=720]+ba/b[height<=720]/bv*+ba/b');
      expect(options.where((f) => f.kind == DownloadKind.video).map((f) => f.label), ['1080p', '720p', '480p', '360p']);
    });

    test('audio choices: MP3 and the original M4A', () {
      final audio = MediaFormat.listOptions().where((f) => f.kind == DownloadKind.audio).toList();
      expect(audio.map((f) => f.extension), ['mp3', 'm4a']);
      expect(audio.first.convert, 'mp3:192');
      expect(audio.last.selector, 'ba[ext=m4a]/ba/b');
    });
  });
}
