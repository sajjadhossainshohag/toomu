import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:toomu/app/data/models/track.dart';
import 'package:toomu/app/services/audio_player_service.dart';

Track _song(String name) => Track(
      id: 'local:$name',
      title: name,
      uri: 'file:///music/$name.mp3',
      path: '/music/$name.mp3',
      album: 'Album',
      duration: const Duration(minutes: 3),
      localSongId: name.length,
      albumId: 7,
      dateAdded: 1700000000,
    );

void main() {
  test('a song survives saving and loading', () {
    final t = Track.fromJson(_song('a').toJson());
    expect(t.id, 'local:a');
    expect(t.path, '/music/a.mp3');
    expect(t.uri, 'file:///music/a.mp3');
    expect(t.duration, const Duration(minutes: 3));
    expect(t.localSongId, 1);
    expect(t.albumId, 7);
    expect(t.dateAdded, 1700000000);
    expect(t.album, 'Album');
  });

  test('only files are restorable, not YouTube streams', () {
    expect(_song('a').restorable, isTrue);
    final stream = Track(
      id: 'yt:x',
      title: 'x',
      uri: 'http://127.0.0.1/x',
      sourceBuilder: (item) => AudioSource.uri(Uri.parse('http://127.0.0.1/x')),
    );
    expect(stream.restorable, isFalse);
  });

  group('restoring the last queue', () {
    final a = _song('a'), b = _song('b'), c = _song('c');

    test('continues at the same song and position', () {
      final r = AudioPlayerService.restoredQueue([a, b, c], [true, true, true], 1, const Duration(seconds: 42))!;
      expect(r.tracks, [a, b, c]);
      expect(r.index, 1);
      expect(r.position, const Duration(seconds: 42));
    });

    test('songs deleted meanwhile are left out and the index follows', () {
      final r = AudioPlayerService.restoredQueue([a, b, c], [false, true, true], 2, const Duration(seconds: 5))!;
      expect(r.tracks, [b, c]);
      expect(r.index, 1);
      expect(r.position, const Duration(seconds: 5));
    });

    test('the current song deleted: starts at the first one from the beginning', () {
      final r = AudioPlayerService.restoredQueue([a, b, c], [true, false, true], 1, const Duration(seconds: 5))!;
      expect(r.tracks, [a, c]);
      expect(r.index, 0);
      expect(r.position, Duration.zero);
    });

    test('nothing left: nothing restored', () {
      expect(AudioPlayerService.restoredQueue([a], [false], 0, Duration.zero), isNull);
    });
  });
}
