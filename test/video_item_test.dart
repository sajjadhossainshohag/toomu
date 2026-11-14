import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/data/models/video_item.dart';

void main() {
  test('MediaStore row → VideoItem', () {
    final v = VideoItem.fromMediaStore({
      'id': 42,
      'name': 'Holiday.mp4',
      'title': '',
      'duration': 125000,
      'path': '/storage/emulated/0/DCIM/Camera/Holiday.mp4',
      'size': 52428800,
      'width': 1920,
      'height': 1080,
      'dateAdded': 1700000000,
      'folder': 'Camera',
      'uri': 'content://media/external/video/media/42',
    });
    expect(v.title, 'Holiday'); // falls back to the file name without extension
    expect(v.duration, const Duration(seconds: 125));
    expect(v.quality, '1080p');
    expect(v.isLandscape, isTrue);
    expect(v.playable, '/storage/emulated/0/DCIM/Camera/Holiday.mp4');
    expect(v.resumeKey, v.path);
  });

  test('portrait phone video and 4K labels', () {
    expect(const VideoItem(uri: 'x', title: 't', width: 1080, height: 1920).isLandscape, isFalse);
    expect(const VideoItem(uri: 'x', title: 't', width: 1080, height: 1920).quality, '1080p');
    expect(const VideoItem(uri: 'x', title: 't', width: 3840, height: 2160).quality, '4K');
    expect(const VideoItem(uri: 'x', title: 't').quality, isNull);
  });

  test('files opened from other apps', () {
    final f = VideoItem.file('content://com.android.providers/document/123', name: 'Movie (2024).mkv');
    expect(f.title, 'Movie (2024)');
    expect(f.path, isNull);
    expect(f.playable, 'content://com.android.providers/document/123');

    final d = VideoItem.file('/storage/emulated/0/Download/Toomu/Video/Clip (720p).mp4');
    expect(d.title, 'Clip (720p)');
    expect(d.playable, '/storage/emulated/0/Download/Toomu/Video/Clip (720p).mp4');
  });
}
