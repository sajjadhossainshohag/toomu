import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../models/youtube_stream.dart';
import '../models/yt_info.dart';

/// One page of video search results (see [YoutubeProvider.search]).
class VideoPage {
  VideoPage._(this.videos, this._list);

  final List<Video> videos;
  final SearchList _list;

  Future<VideoPage?> nextPage() async {
    final next = await _list.nextPage();
    return next == null ? null : VideoPage._(YoutubeProvider._toVideos(next), next);
  }
}

/// YouTube search, home feed and video details (youtube_explode_dart).
/// Downloading and audio streaming are done by yt-dlp (YtDlpService).
class YoutubeProvider {
  YoutubeProvider() : _yt = YoutubeExplode();

  final YoutubeExplode _yt;

  // ----------------------------------------------------------------- search

  /// Video search. Uses `searchContent` and maps results ourselves: the
  /// library's `search()` throws a FormatException on some "Streamed …"
  /// upload dates, which broke whole result pages.
  Future<VideoPage> search(String query) async {
    final list = await _yt.search.searchContent(query, filter: TypeFilters.video);
    return VideoPage._(_toVideos(list), list);
  }

  static List<Video> _toVideos(Iterable<SearchResult> results) => results
      .whereType<SearchVideo>()
      .map((e) => Video(
            e.id,
            e.title,
            e.author,
            ChannelId(e.channelId),
            null,
            e.uploadDate,
            null,
            e.description,
            _parseDuration(e.duration),
            ThumbnailSet(e.id.value),
            null,
            Engagement(e.viewCount, null, null),
            e.isLive,
          ))
      .toList();

  /// "1:02:03" / "12:34" → Duration; null for live or unparsable.
  static Duration? _parseDuration(String raw) {
    final parts = raw.trim().split(':');
    if (parts.isEmpty || parts.length > 3) return null;
    var seconds = 0;
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null) return null;
      seconds = seconds * 60 + n;
    }
    return seconds == 0 ? null : Duration(seconds: seconds);
  }

  Future<Video> video(String videoId) => _yt.videos.get(videoId);

  // ------------------------------------------------- fast format listing

  /// The download sheet's quality list in ~0.3 s, without yt-dlp (no
  /// Python start-up, no JS challenge). Only *metadata* is used: options are
  /// yt-dlp selectors, so yt-dlp still picks working streams at download
  /// time. Returns null if YouTube refuses these clients.
  Future<YtInfo?> quickInfo(String videoId, {Duration? duration}) async {
    for (final clients in [
      [YoutubeApiClient.android],
      [YoutubeApiClient.androidVr],
      [YoutubeApiClient.ios],
    ]) {
      try {
        final m = await _yt.videos.streams
            .getManifest(videoId, ytClients: clients, requireWatchPage: false)
            .timeout(const Duration(seconds: 5));
        if (m.videoOnly.isEmpty && m.audioOnly.isEmpty) continue;
        return YtInfo(
          id: videoId,
          title: '',
          uploader: '',
          duration: duration,
          formats: [for (final s in m.streams) _toFormat(s)],
        );
      } catch (_) {
        // Try the next client.
      }
    }
    return null;
  }

  /// Streams for watching right away (no yt-dlp, well under a second) —
  /// but only links YouTube actually serves: each client's best video link
  /// is test-fetched (first byte) before it's used, since YouTube refuses
  /// some clients' links outright. Null when no client's links work.
  Future<({YtInfo info, String client})?> playableInfo(String videoId, {Duration? duration}) async {
    // Clients whose links need no signature deciphering, most likely to
    // work first.
    final clients = <(String, YoutubeApiClient)>[
      ('android_sdkless', YoutubeApiClient.androidSdkless),
      ('android_vr', YoutubeApiClient.androidVr),
      ('android', YoutubeApiClient.android),
      ('ios', YoutubeApiClient.ios),
    ];
    for (final (name, client) in clients) {
      try {
        final m = await _yt.videos.streams
            .getManifest(videoId, ytClients: [client], requireWatchPage: false)
            .timeout(const Duration(seconds: 5));
        final agent = (client.payload['context'] as Map?)?['client']?['userAgent'] as String?;
        final headers = agent == null ? const <String, String>{} : {'User-Agent': agent};
        final info = YtInfo(
          id: videoId,
          title: '',
          uploader: '',
          duration: duration,
          formats: [for (final s in m.streams) _toFormat(s, headers: headers)],
        );
        final best = YoutubeStream.qualities(info);
        if (best.isEmpty) continue; // no separate HD streams from this client
        if (await _serves(best.first.videoUri, headers)) return (info: info, client: name);
        debugPrint('[YouTube] fast links from $name refused');
      } catch (_) {
        // Try the next client.
      }
    }
    return null;
  }

  /// Whether YouTube serves [url] (fetches its first byte).
  static Future<bool> _serves(String url, Map<String, String> headers) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final req = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 3));
      headers.forEach(req.headers.set);
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
      final res = await req.close().timeout(const Duration(seconds: 3));
      await res.drain<void>();
      return res.statusCode == 206 || res.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  static YtFormat _toFormat(StreamInfo s, {Map<String, String> headers = const {}}) {
    final video = s is VideoStreamInfo ? s : null;
    final audio = s is AudioStreamInfo ? s : null;
    final mp4 = s.container == StreamContainer.mp4;
    final track = audio?.audioTrack;
    return YtFormat(
      formatId: '${s.tag}',
      // Same extensions yt-dlp reports (audio-only MP4 = m4a).
      ext: video == null && mp4 ? 'm4a' : s.container.name,
      vcodec: video?.videoCodec ?? 'none',
      acodec: audio?.audioCodec ?? 'none',
      width: video?.videoResolution.width,
      height: video?.videoResolution.height,
      fps: video?.framerate.framesPerSecond.toDouble(),
      filesize: s.size.totalBytes,
      abr: video == null ? s.bitrate.kiloBitsPerSecond : null,
      // ANDROID-client URL: plays with plain Range requests (fast "Play
      // audio"); yt-dlp's URL is the fallback if YouTube cuts it off.
      url: s.url.toString(),
      httpHeaders: headers,
      // yt-dlp ranks the original language highest; dubs below.
      languagePreference: audio == null ? null : (track == null || track.audioIsDefault ? 10 : -1),
    );
  }

  void dispose() => _yt.close();
}
