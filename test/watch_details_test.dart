import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/data/providers/youtube_provider.dart';
import 'package:toomu/app/modules/video_player/controllers/watch_details_controller.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

Video _video(String id, String title) => Video(VideoId(id), title, 'Some Channel', ChannelId('UC${'b' * 22}'), null,
    '2 days ago', null, 'About this video', const Duration(minutes: 4), ThumbnailSet(id), null,
    const Engagement(123456, 900, null), false);

class _Source implements WatchSource {
  bool failVideo = false;
  bool failRelated = false;
  bool commentsOff = false;

  @override
  Future<Video> video(String videoId) async {
    if (failVideo) throw StateError('offline');
    return _video(videoId, 'The video');
  }

  @override
  Future<Channel> channel(ChannelId id) async => Channel(id, 'Some Channel', 'https://logo', 'https://banner', 1200000);

  @override
  Future<List<Video>> related(Video video) async {
    if (failRelated) throw StateError('related broke');
    return [_video('bbbbbbbbbbb', 'Next one'), _video('ccccccccccc', 'Another')];
  }

  @override
  Future<({List<Comment> comments, int total})?> comments(Video video) async => commentsOff
      ? null
      : (comments: [Comment('@fan', ChannelId('UC${'c' * 22}'), 'Great video', 12, '1 day ago', 2, false, null)], total: 340);
}

void main() {
  test('details, channel, comments and Up next all load', () async {
    final c = WatchDetailsController('aaaaaaaaaaa', _Source());
    await c.load();
    expect(c.video.value?.title, 'The video');
    expect(c.channel.value?.subscribersCount, 1200000);
    expect(c.related.map((v) => v.title), ['Next one', 'Another']);
    expect(c.comments.single.text, 'Great video');
    expect(c.commentCount.value, 340);
    expect(c.loading.value, isFalse);
  });

  test('one part failing leaves the others', () async {
    final c = WatchDetailsController('aaaaaaaaaaa', _Source()..failRelated = true);
    await c.load();
    expect(c.related, isEmpty);
    expect(c.comments, isNotEmpty);
    expect(c.channel.value, isNotNull);
  });

  test('comments turned off are said so, not shown as an empty list', () async {
    final c = WatchDetailsController('aaaaaaaaaaa', _Source()..commentsOff = true);
    await c.load();
    expect(c.commentsOff.value, isTrue);
  });

  test('details that fail to load say why, and Try again loads them', () async {
    final source = _Source()..failVideo = true;
    final c = WatchDetailsController('aaaaaaaaaaa', source);
    await c.load();
    expect(c.video.value, isNull);
    expect(c.error.value, isNotNull);
    source.failVideo = false;
    await c.load();
    expect(c.video.value?.title, 'The video');
    expect(c.error.value, isNull);
  });
}
