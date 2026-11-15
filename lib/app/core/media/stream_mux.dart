import 'mp4_boxes.dart';
import 'mp4_reader.dart';
import 'mp4_writer.dart';
import 'ts_reader.dart';

abstract class StreamMux {
  static void mux({
    required List<String> videoRuns,
    required List<String> audioRuns,
    required String out,
    bool audioOnly = false,
  }) {
    // Run files are named by container (.mp4 = fMP4/MP4, .ts, .aac). With no
    // separate audio runs, audio is taken from the video runs (muxed streams).
    final ts = <String, TsTracks>{};
    MediaTrack? read(String path, {required bool video}) {
      if (path.endsWith('.ts')) {
        final tracks = ts[path] ??= TsReader.read(path, '$path.samples');
        return video ? tracks.video : tracks.audio;
      }
      if (path.endsWith('.aac')) return video ? null : TsReader.readAac(path);
      return Mp4Reader.read(path, video ? 'vide' : 'soun');
    }

    final video = audioOnly
        ? <MediaTrack>[]
        : [for (final p in videoRuns) read(p, video: true)].whereType<MediaTrack>().toList();
    final audio = [
      for (final p in audioRuns.isNotEmpty ? audioRuns : videoRuns) read(p, video: false),
    ].whereType<MediaTrack>().toList();
    if (video.isEmpty && audio.isEmpty) {
      throw const FormatException('No video or audio found in the downloaded stream');
    }
    Mp4Writer.write(out, [video, audio]);
  }
}
