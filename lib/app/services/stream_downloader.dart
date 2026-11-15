import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/media/stream_mux.dart';
import '../core/utils/media_manifest.dart';
import '../core/utils/stream_plan.dart';
import '../data/models/download_task.dart';

typedef FileFetcher = Future<void> Function(
  String url,
  Map<String, String> headers,
  String path,
  CancelToken token,
  void Function(int bytes) onBytes,
);

class StreamCanceled implements Exception {
  const StreamCanceled();
}

class StreamDownloader {
  StreamDownloader({required this.dio, required this.native, this.connections = 4, this.fetchFile});

  final Dio dio;
  final MethodChannel native;
  final int connections;
  final FileFetcher? fetchFile;

  Future<String> download({
    required String url,
    required Map<String, String> headers,
    required String work,
    int maxHeight = 0,
    bool audioOnly = false,
    CancelToken? cancel,
    void Function(int done)? onBytes,
    void Function(int total)? onTotal,
    void Function(DownloadPhase phase)? onPhase,
  }) async {
    final token = cancel ?? CancelToken();
    // The page's cookies only go to its own host, not to CDNs.
    final host = Uri.parse(url).host;
    Map<String, String> headersFor(String u) =>
        Uri.tryParse(u)?.host == host ? headers : ({...headers}..remove('Cookie'));

    onPhase?.call(DownloadPhase.lookingUp);
    final text = await _text(url, headers, token);
    StreamTrack? video;
    StreamTrack? audio;
    if (text.trimLeft().startsWith('#EXTM3U')) {
      final info = MediaManifest.parseHls(text, Uri.parse(url));
      if (info.protected) throw StreamPlanner.drm;
      if (info.variants.isEmpty) {
        final track = StreamPlanner.hlsMedia(text, Uri.parse(url));
        if (audioOnly) {
          audio = track;
        } else {
          video = track;
        }
      } else {
        final v = StreamPlanner.pickVariant(info.variants, maxHeight);
        final r = StreamPlanner.audioFor(v, info.renditions);
        if (r != null) audio = StreamPlanner.hlsMedia(await _text(r.url, headersFor(r.url), token), Uri.parse(r.url));
        if (!audioOnly || r == null) {
          video = StreamPlanner.hlsMedia(await _text(v.url, headersFor(v.url), token), Uri.parse(v.url));
        }
      }
    } else {
      final plan = StreamPlanner.dash(text, Uri.parse(url), maxHeight: maxHeight, audioOnly: audioOnly);
      video = plan.video;
      audio = plan.audio;
    }
    _check(token);

    await Directory(work).create(recursive: true);
    final tracks = [if (video != null) ('video', video), if (audio != null) ('audio', audio)];
    final count = tracks.fold<int>(0, (n, t) => n + t.$2.partCount);
    var done = 0;
    var finished = 0;
    final files = <String, List<String>>{'video': [], 'audio': []};
    for (final (name, track) in tracks) {
      onPhase?.call(name == 'audio' && video != null ? DownloadPhase.audio : DownloadPhase.video);
      for (var k = 0; k < track.runs.length; k++) {
        files[name]!.add(await _fetchRun(
          track.runs[k],
          '$work/$name-$k',
          headersFor,
          token,
          (bytes) {
            done += bytes;
            onBytes?.call(done);
          },
          () {
            finished++;
            onTotal?.call(done * count ~/ finished);
          },
        ));
      }
    }
    _check(token);

    onPhase?.call(DownloadPhase.merging);
    final muxed = '$work/muxed.mp4';
    // With only video runs, a muxed stream's own audio is used.
    final audioOnlyFromVideo = audioOnly && files['audio']!.isEmpty;
    await _mux(
      audioOnlyFromVideo ? const [] : files['video']!,
      audioOnlyFromVideo ? files['video']! : files['audio']!,
      muxed,
      audioOnly,
    );
    final out = '$work/out.${audioOnly ? 'm4a' : 'mp4'}';
    final converted = await native.invokeMethod<bool>('finish', {
      'input': muxed,
      'out': out,
      'audioOnly': audioOnly,
    });
    return converted == true ? out : muxed;
  }

  static Future<void> _mux(List<String> video, List<String> audio, String out, bool audioOnly) =>
      Isolate.run(() => StreamMux.mux(videoRuns: video, audioRuns: audio, out: out, audioOnly: audioOnly));

  Future<String> _fetchRun(
    StreamRun run,
    String dir,
    Map<String, String> Function(String url) headersFor,
    CancelToken token,
    void Function(int bytes) onChunk,
    void Function() onPart,
  ) async {
    final parts = run.parts;
    final out = '$dir.${run.extension}';
    if (File(out).existsSync()) {
      onChunk(File(out).lengthSync());
      for (var i = 0; i < parts.length; i++) {
        onPart();
      }
      return out;
    }

    final single = parts.length == 1 && parts.first.range == null && parts.first.keyUrl == null;
    if (single && fetchFile != null) {
      // One whole file (DASH SegmentBase): parallel ranged, resumable fetch.
      var last = 0;
      await fetchFile!(parts.first.url, headersFor(parts.first.url), '$out.part', token, (b) {
        onChunk(b - last);
        last = b;
      });
      await File('$out.part').rename(out);
      onPart();
      return out;
    }

    await Directory(dir).create(recursive: true);
    final keys = <String, Future<Uint8List>>{};
    final pending = Queue<int>.of(List.generate(parts.length, (i) => i));
    final local = CancelToken();
    unawaited(token.whenCancel.then((e) => local.cancel(e.error)));

    Future<void> worker() async {
      while (pending.isNotEmpty && !local.isCancelled) {
        _check(token);
        final i = pending.removeFirst();
        final p = parts[i];
        final file = File('$dir/$i');
        if (file.existsSync()) {
          onChunk(file.lengthSync());
          onPart();
          continue;
        }
        final temp = File('$dir/$i.part');
        await _retry(() async {
          final sink = temp.openWrite();
          var got = 0;
          try {
            final response = await dio.get<ResponseBody>(
              p.url,
              cancelToken: local,
              options: Options(
                responseType: ResponseType.stream,
                headers: {...headersFor(p.url), if (p.range != null) 'Range': p.range!},
              ),
            );
            await for (final chunk in response.data!.stream) {
              sink.add(chunk);
              got += chunk.length;
              onChunk(chunk.length);
            }
          } catch (_) {
            onChunk(-got); // a retry fetches the piece from the start
            rethrow;
          } finally {
            await sink.close();
          }
        });
        final keyUrl = p.keyUrl;
        if (keyUrl != null) {
          final key = await (keys[keyUrl] ??= _bytes(keyUrl, headersFor(keyUrl), local));
          await native.invokeMethod<void>('decrypt', {'path': temp.path, 'key': key, 'iv': p.iv});
        }
        await temp.rename(file.path);
        onPart();
      }
    }

    try {
      await Future.wait(List.generate(connections.clamp(1, 8), (_) => worker()), eagerError: true);
    } catch (_) {
      if (!local.isCancelled) local.cancel('sibling failed');
      rethrow;
    }
    _check(token);

    final sink = File('$out.part').openWrite();
    try {
      for (var i = 0; i < parts.length; i++) {
        await sink.addStream(File('$dir/$i').openRead());
      }
    } finally {
      await sink.close();
    }
    await File('$out.part').rename(out);
    await Directory(dir).delete(recursive: true);
    return out;
  }

  Future<void> _retry(Future<void> Function() attempt) async {
    for (var tries = 0; ; tries++) {
      try {
        return await attempt();
      } on DioException catch (e) {
        if (CancelToken.isCancel(e) || tries >= 3) rethrow;
        debugPrint('[Stream] piece failed (${e.response?.statusCode ?? e.type}); retrying');
        await Future<void>.delayed(Duration(seconds: 2 * (tries + 1)));
      }
    }
  }

  static void _check(CancelToken token) {
    if (token.isCancelled) throw const StreamCanceled();
  }

  Future<String> _text(String url, Map<String, String> headers, CancelToken token) async {
    final r = await dio.get<String>(
      url,
      cancelToken: token,
      options: Options(responseType: ResponseType.plain, headers: headers),
    );
    return r.data ?? '';
  }

  Future<Uint8List> _bytes(String url, Map<String, String> headers, CancelToken token) async {
    final r = await dio.get<List<int>>(
      url,
      cancelToken: token,
      options: Options(responseType: ResponseType.bytes, headers: headers),
    );
    return Uint8List.fromList(r.data ?? const []);
  }
}
