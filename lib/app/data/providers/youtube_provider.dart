import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../core/utils/subtitles.dart';
import '../models/youtube_stream.dart';
import '../models/yt_info.dart';
import 'youtube/watch_next.dart';

/// A page of videos in the home feed: search results, or the signed-in
/// account's feed.
abstract class FeedPage {
  List<Video> get videos;

  /// The next page; null at the end.
  Future<FeedPage?> nextPage();
}

/// One page of video search results (see [YoutubeProvider.search]).
class VideoPage implements FeedPage {
  VideoPage._(this.videos, this._list);

  @override
  final List<Video> videos;
  final SearchList _list;

  @override
  Future<VideoPage?> nextPage() async {
    final next = await _list.nextPage();
    return next == null ? null : VideoPage._(YoutubeProvider._toVideos(next), next);
  }
}

/// What the watch page shows under the player.
abstract class WatchSource {
  Future<Video> video(String videoId);
  Future<Channel> channel(ChannelId id);
  Future<List<Video>> related(Video video);
  Future<CommentsPage?> comments(Video video); // null: comments are turned off
  Future<List<Comment>> replies(Comment comment);
}

/// What a channel page shows.
abstract class ChannelSource {
  Future<Channel> channel(ChannelId id);
  Future<VideosPage> uploads(ChannelId id, {required bool shorts, required VideoSorting sort});
}

class VideosPage {
  const VideosPage(this.videos, [this.next]);

  final List<Video> videos;
  final Future<VideosPage?> Function()? next;
}

class CommentsPage {
  const CommentsPage(this.comments, this.total, [this.next]);

  final List<Comment> comments;
  final int total;
  final Future<CommentsPage?> Function()? next;
}

/// YouTube search, home feed, video details and the fast stream lookup
/// (youtube_explode_dart). Downloads are done by yt-dlp (YtDlpService).
class YoutubeProvider implements WatchSource, ChannelSource {
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
      .map(
        (e) => Video(
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
        ),
      )
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

  @override
  Future<Video> video(String videoId) => _yt.videos.get(videoId);

  @override
  Future<Channel> channel(ChannelId id) => _yt.channels.get(id);

  @override
  Future<VideosPage> uploads(ChannelId id, {required bool shorts, required VideoSorting sort}) async => _videosPage(
    await _yt.channels.getUploadsFromPage(
      id,
      videoSorting: sort,
      videoType: shorts ? VideoType.shorts : VideoType.normal,
    ),
  );

  VideosPage _videosPage(ChannelUploadsList list) => VideosPage(list.toList(), () async {
    final more = await list.nextPage();
    return more == null ? null : _videosPage(more);
  });

  final _watchNext = WatchNext();

  // Up next and the comments come in one answer, asked for together by the watch page: fetched once.
  final _nextPages = <String, Future<WatchNextPage>>{};
  final _repliesTokens = Expando<String>();

  Future<WatchNextPage> _next(String videoId) {
    if (_nextPages.length >= 10 && !_nextPages.containsKey(videoId)) _nextPages.remove(_nextPages.keys.first);
    final page = _nextPages.putIfAbsent(videoId, () => _watchNext.next(videoId));
    page.then((_) {}, onError: (Object _) => _nextPages.remove(videoId)); // a failure is retried next time
    return page;
  }

  @override
  Future<List<Video>> related(Video video) async => (await _next(video.id.value)).related;

  @override
  Future<CommentsPage?> comments(Video video) async {
    final token = (await _next(video.id.value)).commentsToken;
    return token == null ? null : _commentsPage(await _watchNext.comments(token));
  }

  CommentsPage _commentsPage(WatchNextComments page) {
    for (final c in page.comments) {
      _repliesTokens[c] = page.repliesToken(c);
    }
    final next = page.nextToken;
    return CommentsPage(
      page.comments,
      page.total,
      next == null ? null : () async => _commentsPage(await _watchNext.comments(next)),
    );
  }

  @override
  Future<List<Comment>> replies(Comment comment) async {
    final token = _repliesTokens[comment];
    return token == null ? const [] : (await _watchNext.comments(token)).comments;
  }

  // Up next back and forth, or reopening from History, finds the list here instead of asking YouTube again.
  static final _captionLists = <String, ({DateTime at, Future<List<ClosedCaptionTrackInfo>> tracks})>{};

  Future<List<ClosedCaptionTrackInfo>> captionTracks(String videoId, List<String> langs) {
    final hit = _captionLists[videoId];
    if (hit != null && DateTime.now().difference(hit.at) < const Duration(minutes: 30)) return hit.tracks;
    if (_captionLists.length >= 50) _captionLists.remove(_captionLists.keys.first);
    final tracks = _yt.videos.closedCaptions
        .getManifest(videoId, formats: const [ClosedCaptionFormat.srv3])
        .then((m) => Subtitles.forWatching(m.tracks, langs));
    _captionLists[videoId] = (at: DateTime.now(), tracks: tracks);
    // A failed list isn't kept: the next ask tries again (whoever asked sees the error).
    tracks.then((_) {}, onError: (Object _) => _captionLists.remove(videoId));
    return tracks;
  }

  Future<String?> captionFile(String videoId, ClosedCaptionTrackInfo t, String dir) async {
    final path = '$dir/$videoId.${t.language.code}${t.isAutoGenerated ? '.auto' : ''}.srt';
    if (await File(path).exists()) return path; // picked before in this app run
    return await _writeCaptions(t, path) ? path : null;
  }

  Future<bool> _writeCaptions(ClosedCaptionTrackInfo t, String path) async {
    final track = await _yt.videos.closedCaptions.get(t);
    if (track.captions.isEmpty) return false;
    // Written aside first: a file cut short by a crash would otherwise be taken as done next time.
    final part = File('$path.part');
    await part.writeAsString(Subtitles.srt(track.captions));
    await part.rename(path);
    return true;
  }

  Future<List<String>> saveSubtitles(String videoId, String videoPath, List<String> langs) async {
    final manifest = await _yt.videos.closedCaptions.getManifest(videoId, formats: const [ClosedCaptionFormat.srv3]);
    final saved = <String>[];
    for (final t in Subtitles.pick(manifest.tracks, langs)) {
      try {
        final path = Subtitles.sidecarPath(videoPath, t.language.code);
        if (await _writeCaptions(t, path)) saved.add(path);
      } catch (e) {
        debugPrint('[YouTube] ${t.language.code} subtitles failed: $e');
      }
    }
    return saved;
  }

  // ------------------------------------------------------- fast lookup

  /// YouTube's visionOS app client: whole-file links up to 4K with no JS
  /// challenge and no PO token — what yt-dlp, NewPipe and Grayjay use since
  /// mid-2026 (measured Nov 2026: ~0.2 s per lookup, every file served to
  /// the end). Without a visitor id YouTube asks to sign in.
  static const _visionOsAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 '
      '(KHTML, like Gecko) Version/26.0 Safari/605.1.15';

  static YoutubeApiClient _visionOs(String visitorData) => YoutubeApiClient(
    {
      'context': {
        'client': {
          'clientName': 'VISIONOS',
          'clientVersion': '1.02',
          'deviceMake': 'Apple',
          'deviceModel': 'RealityDevice17,1',
          'userAgent': _visionOsAgent,
          'osName': 'visionOS',
          'osVersion': '26.5.23O471',
          'hl': 'en',
          'timeZone': 'UTC',
          'utcOffsetMinutes': 0,
          'visitorData': visitorData,
        },
      },
      'contentCheckOk': true,
      'racyCheckOk': true,
    },
    'https://www.youtube.com/youtubei/v1/player?prettyPrint=false',
    headers: {'X-Goog-Visitor-Id': visitorData},
  );

  /// Anonymous YouTube visitor id, fetched once and kept for hours.
  static String? _visitorData;
  static DateTime _visitorAt = DateTime(0);
  static Future<String?>? _visitorInFlight;

  /// Fetches the visitor id ahead of time (first Watch tap is faster).
  void warmUp() => unawaited(_visitor());

  static Future<String?> _visitor({bool fresh = false}) {
    if (!fresh && _visitorData != null && DateTime.now().difference(_visitorAt) < const Duration(hours: 6)) {
      return Future.value(_visitorData);
    }
    return _visitorInFlight ??= () async {
      try {
        // A tiny endpoint first; the home page (large) if that ever changes.
        for (final (url, pattern) in [
          ('https://www.youtube.com/sw.js_data', RegExp(r'"(Cg[A-Za-z0-9_\-%]{20,})"')),
          ('https://www.youtube.com/', RegExp(r'"VISITOR_DATA":"([^"]+)"')),
        ]) {
          final body = await _get(url);
          final found = body == null ? null : pattern.firstMatch(body)?.group(1);
          if (found != null) {
            _visitorData = found;
            _visitorAt = DateTime.now();
            return found;
          }
        }
        return null;
      } finally {
        _visitorInFlight = null;
      }
    }();
  }

  static Future<String?> _get(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 5));
      req.headers.set(HttpHeaders.userAgentHeader, _visionOsAgent);
      final res = await req.close().timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return null;
      return await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 8));
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  // Shared by every instance: the sheet's lookup is reused by downloads.
  static final Map<String, ({DateTime at, FastLinks links})> _fastCache = {};
  static final Map<String, Future<FastLinks?>> _fastInFlight = {};

  /// Formats and stream links without yt-dlp (no Python, no JS challenge),
  /// for the download sheet's list, "Watch" and "Play audio". Each client's
  /// links are test-fetched before use. Null when no client works.
  Future<FastLinks?> fastLinks(String videoId, {Duration? duration}) {
    final cached = _fastCache[videoId];
    if (cached != null && DateTime.now().difference(cached.at) < const Duration(minutes: 30)) {
      return Future.value(cached.links);
    }
    return _fastInFlight[videoId] ??= _fastLookup(videoId, duration)
        .then((links) {
          if (links != null) {
            _fastCache[videoId] = (at: DateTime.now(), links: links);
            if (_fastCache.length > 30) _fastCache.remove(_fastCache.keys.first);
          }
          return links;
        })
        .whenComplete(() {
          _fastInFlight.remove(videoId);
        });
  }

  /// The sheet's quality list (metadata only).
  Future<YtInfo?> quickInfo(String videoId, {Duration? duration}) =>
      fastLinks(videoId, duration: duration).then((l) => l?.info);

  Future<FastLinks?> _fastLookup(String videoId, Duration? duration) async {
    final sw = Stopwatch()..start();
    // visionOS: whole files. Android: only about the first minute without a
    // PO token (Nov 2026) — still good for an instant start; the stream
    // proxy carries on with yt-dlp's links.
    for (final name in ['visionos', 'android_sdkless', 'android']) {
      try {
        final YoutubeApiClient client;
        if (name == 'visionos') {
          final visitor = await _visitor();
          if (visitor == null) continue;
          client = _visionOs(visitor);
        } else {
          client = name == 'android' ? YoutubeApiClient.android : YoutubeApiClient.androidSdkless;
        }
        StreamManifest manifest;
        try {
          manifest = await _manifest(videoId, client);
        } on VideoUnplayableException {
          if (name != 'visionos') rethrow;
          // "Sign in to confirm you're not a bot": a stale visitor id.
          final visitor = await _visitor(fresh: true);
          if (visitor == null) rethrow;
          manifest = await _manifest(videoId, _visionOs(visitor));
        }
        final agent = (client.payload['context'] as Map?)?['client']?['userAgent'] as String?;
        final headers = agent == null ? const <String, String>{} : {'User-Agent': agent};
        final info = YtInfo(
          id: videoId,
          title: '',
          uploader: '',
          duration: duration,
          formats: [
            for (final s in manifest.streams)
              if (s is! HlsVideoStreamInfo && s is! HlsAudioStreamInfo && s is! HlsMuxedStreamInfo)
                _toFormat(s, headers: headers),
          ],
        );
        final test = YoutubeStream.qualities(info).firstOrNull?.videoUri ?? info.bestAudio?.url;
        if (test == null) continue;
        // A link that serves the end of its file is a whole-file link
        // (Grayjay's check); one that only serves the start is not.
        final full = await serves(test, headers, tail: true);
        if (!full && !await serves(test, headers)) {
          debugPrint('[YouTube] fast links from $name refused');
          continue;
        }
        debugPrint(
          '[YouTube] fast lookup: $name${full ? '' : ' (first minute only)'} '
          'in ${sw.elapsedMilliseconds} ms',
        );
        return FastLinks(info, name, full: full);
      } catch (e) {
        debugPrint('[YouTube] fast lookup $name failed: ${e.toString().split('\n').first}');
      }
    }
    return null;
  }

  Future<StreamManifest> _manifest(String videoId, YoutubeApiClient client) => _yt.videos.streams
      .getManifest(videoId, ytClients: [client], requireWatchPage: false)
      .timeout(const Duration(seconds: 6));

  /// Whether YouTube serves [url]'s first byte — or with [tail], its last
  /// bytes — asked for the way the stream proxy asks (`range=` parameter).
  static HttpClient Function(Uri url)? pooledClient;

  @visibleForTesting
  static Future<bool> serves(String url, Map<String, String> headers, {bool tail = false}) async {
    final length = int.tryParse(Uri.parse(url).queryParameters['clen'] ?? '');
    if (tail && (length == null || length < 1024)) return false;
    final range = tail ? '${length! - 512}-${length - 1}' : '0-0';
    // The stream proxy's pool: playback reuses this connection, and it has the link's IP version.
    final pooled = pooledClient?.call(Uri.parse(url));
    final client = pooled ?? (HttpClient()..connectionTimeout = const Duration(seconds: 3));
    try {
      final req = await client.getUrl(Uri.parse('$url&range=$range')).timeout(const Duration(seconds: 3));
      headers.forEach(req.headers.set);
      final res = await req.close().timeout(const Duration(seconds: 3));
      await res.drain<void>();
      return res.statusCode == 206 || res.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      if (pooled == null) client.close(force: true);
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
      tbr: s.bitrate.kiloBitsPerSecond,
      // Played through the stream proxy (see StreamProxy).
      url: s.url.toString(),
      httpHeaders: headers,
      // yt-dlp ranks the original language highest; dubs below.
      languagePreference: audio == null ? null : (track == null || track.audioIsDefault ? 10 : -1),
    );
  }

  void dispose() => _yt.close();
}

/// Stream links from the fast lookup (no yt-dlp).
class FastLinks {
  const FastLinks(this.info, this.client, {required this.full});

  final YtInfo info;

  /// Which YouTube client they came from (for the logs).
  final String client;

  /// Whole files are served (visionOS). False: only about the first minute
  /// (Android client without a PO token); the stream proxy carries on with
  /// yt-dlp's links.
  final bool full;
}
