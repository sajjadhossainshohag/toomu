import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/data/models/saved_videos.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

Video _video(String id, {Duration? duration = const Duration(minutes: 3)}) => Video(VideoId(id), 'Video $id',
    'Cabin Builders', ChannelId('UC${'b' * 22}'), null, null, null, '', duration, ThumbnailSet(id), null,
    const Engagement(1200, null, null), false);

void main() {
  test('a saved video comes back with what its row shows', () {
    final back = SavedVideos.read(SavedVideos.write([_video('aaaaaaaaaaa')])).single;
    expect(back.id.value, 'aaaaaaaaaaa');
    expect(back.title, 'Video aaaaaaaaaaa');
    expect(back.author, 'Cabin Builders');
    expect(back.channelId.value, 'UC${'b' * 22}');
    expect(back.duration, const Duration(minutes: 3));
    expect(back.engagement.viewCount, 1200);
  });

  test('a live video without a length survives too', () {
    expect(SavedVideos.read(SavedVideos.write([_video('aaaaaaaaaaa', duration: null)])).single.duration, isNull);
  });

  test('one broken entry does not hide the rest', () {
    final list = SavedVideos.read([
      {'id': 'bad'},
      SavedVideos.toJson(_video('bbbbbbbbbbb')),
    ]);
    expect(list.map((v) => v.id.value), ['bbbbbbbbbbb']);
    expect(SavedVideos.read(null), isEmpty);
  });

  test('watching again moves a video to the top instead of adding it twice; the list is capped', () {
    var list = <Video>[];
    for (final id in ['aaaaaaaaaaa', 'bbbbbbbbbbb', 'aaaaaaaaaaa']) {
      list = SavedVideos.add(list, _video(id));
    }
    expect(list.map((v) => v.id.value), ['aaaaaaaaaaa', 'bbbbbbbbbbb']);
    for (var i = 0; i < SavedVideos.cap + 5; i++) {
      list = SavedVideos.add(list, _video('v${i.toString().padLeft(10, '0')}'));
    }
    expect(list, hasLength(SavedVideos.cap));
  });
}
