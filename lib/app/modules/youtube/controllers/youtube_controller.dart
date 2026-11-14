import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../../core/utils/error_text.dart';
import '../../../extractors/direct_file_extractor.dart';
import '../../../core/utils/link_parser.dart';
import '../../../core/utils/video_matcher.dart';
import '../../../core/values/app_constants.dart';
import '../../../data/models/media_format.dart';
import '../../../data/models/video_item.dart';
import '../../../data/models/video_meta.dart';
import '../../../data/models/yt_info.dart';
import '../../../data/models/youtube_stream.dart';
import '../../../routes/app_pages.dart';
import '../../video_player/controllers/video_playback_controller.dart';
import '../../../data/models/track.dart';
import '../../../data/providers/youtube_provider.dart';
import '../../../services/audio_player_service.dart';
import '../../../services/download_service.dart';
import '../../../services/remote_config_service.dart';
import '../../../services/storage_service.dart';
import '../../../data/providers/ytdlp/ytdlp_bridge.dart';
import '../../../services/ytdlp_service.dart';
import '../views/widgets/format_sheet.dart';

/// A home-feed category. YouTube has no public "trending" API, so each
/// category is backed by a search query.
class FeedCategory {
  const FeedCategory(this.label, this.query, this.icon);

  final String label;

  /// null = personalised ("For you"): built from search history.
  final String? query;
  final IconData icon;
}

class YoutubeController extends GetxController {
  final YoutubeProvider _yt = YoutubeProvider();
  final _storage = StorageService.to;

  final searchText = TextEditingController();
  final history = <String>[].obs;

  // ---- Search mode (user typed a query) ---------------------------------
  final searching = false.obs;
  final searchQuery = ''.obs;
  final results = <Video>[].obs;
  final loading = false.obs;
  final loadingMore = false.obs;
  final error = RxnString();
  VideoPage? _page;

  // ---- Home feed ---------------------------------------------------------
  static const _builtInCategories = <FeedCategory>[
    FeedCategory('For you', null, Icons.auto_awesome_rounded),
    FeedCategory('Music', 'new music video 2026', Icons.music_note_rounded),
    FeedCategory('Trending', 'trending videos today', Icons.local_fire_department_rounded),
    FeedCategory('Gaming', 'gaming highlights', Icons.sports_esports_rounded),
    FeedCategory('News', 'news today', Icons.newspaper_rounded),
    FeedCategory('Sports', 'sports highlights', Icons.sports_soccer_rounded),
    FeedCategory('Podcasts', 'podcast full episode', Icons.podcasts_rounded),
    FeedCategory('Comedy', 'funny videos', Icons.sentiment_very_satisfied_rounded),
  ];

  /// "For you" always first; the rest from remote config when provided.
  static List<FeedCategory> get categories {
    final remote = RemoteConfigService.to.feedCategories;
    if (remote.isEmpty) return _builtInCategories;
    return [
      _builtInCategories.first,
      for (final c in remote) FeedCategory(c.label, c.query, Icons.label_rounded),
    ];
  }

  final feedIndex = 0.obs;
  final feed = <Video>[].obs;
  final feedLoading = false.obs;
  final feedLoadingMore = false.obs;
  final feedError = RxnString();
  VideoPage? _feedPage;
  final Map<int, ({List<Video> items, VideoPage? page})> _feedCache = {};

  // Format sheet state
  final selectedVideo = Rxn<VideoMeta>();
  final formatsLoading = false.obs;
  final formatsError = RxnString();
  final formatsStatus = ''.obs;
  final videoFormats = <MediaFormat>[].obs;
  final audioFormats = <MediaFormat>[].obs;
  final streamingAudio = false.obs;
  final openingVideo = false.obs;

  @override
  void onInit() {
    super.onInit();
    history.assignAll(
        (_storage.read<List>(AppConstants.kSearchHistory) ?? const []).cast<String>());
  }

  @override
  void onReady() {
    super.onReady();
    loadFeed();
  }

  @override
  void onClose() {
    searchText.dispose();
    _yt.dispose();
    super.onClose();
  }

  // ------------------------------------------------------------------- feed

  String _feedQuery(int index) {
    final q = categories[index].query;
    if (q != null) return q;
    // "For you": lean on what the user searched recently.
    return history.isNotEmpty ? history.first : 'popular music videos';
  }

  void selectCategory(int index) {
    if (index == feedIndex.value && feed.isNotEmpty) return;
    feedIndex.value = index;
    final cached = _feedCache[index];
    if (cached != null) {
      feed.assignAll(cached.items);
      _feedPage = cached.page;
      feedError.value = null;
    } else {
      loadFeed();
    }
  }

  Future<void> loadFeed({bool refresh = false}) async {
    final index = feedIndex.value;
    if (refresh) _feedCache.remove(index);
    feedLoading.value = !refresh || feed.isEmpty;
    feedError.value = null;
    try {
      final page = await _yt.search(_feedQuery(index));
      if (index != feedIndex.value) return; // user switched meanwhile
      _feedPage = page;
      feed.assignAll(_downloadable(page.videos));
      _feedCache[index] = (items: feed.toList(), page: page);
    } catch (e) {
      debugPrint('[YouTube] feed failed: $e');
      if (index == feedIndex.value) feedError.value = ErrorText.of(e);
    } finally {
      if (index == feedIndex.value) feedLoading.value = false;
    }
  }

  Future<void> loadMoreFeed() async {
    final page = _feedPage;
    if (page == null || feedLoadingMore.value || feedLoading.value) return;
    final index = feedIndex.value;
    feedLoadingMore.value = true;
    try {
      final next = await page.nextPage();
      if (next != null && index == feedIndex.value) {
        _feedPage = next;
        feed.addAll(_downloadable(next.videos));
        _feedCache[index] = (items: feed.toList(), page: next);
      }
    } catch (_) {
      // Ignore paging failures; user can scroll again.
    } finally {
      feedLoadingMore.value = false;
    }
  }

  /// Live streams (no duration) can't be downloaded; keep them out.
  static Iterable<Video> _downloadable(Iterable<Video> list) =>
      list.where((v) => v.duration != null && v.duration! > Duration.zero);

  // ----------------------------------------------------------------- search

  /// Link → straight to the format picker. Text → YouTube search.
  Future<void> submit(String input) async {
    final text = input.trim();
    if (text.isEmpty) return;
    final id = LinkParser.youtubeVideoId(text);
    if (id != null) return openVideo(id);
    // 1DM-style: any direct file link downloads as-is.
    final uri = Uri.tryParse(text);
    if (uri != null && const DirectFileExtractor().canHandle(uri)) {
      return DirectFileExtractor.confirmAndDownload(text);
    }
    _remember(text);
    await search(text);
  }

  Future<void> search(String query) async {
    searching.value = true;
    searchQuery.value = query;
    loading.value = true;
    error.value = null;
    results.clear();
    try {
      _page = await _yt.search(query);
      results.assignAll(_page!.videos);
    } catch (e) {
      debugPrint('[YouTube] search failed: $e');
      error.value = ErrorText.of(e);
    } finally {
      loading.value = false;
    }
  }

  Future<void> loadMore() async {
    final page = _page;
    if (page == null || loadingMore.value || loading.value) return;
    loadingMore.value = true;
    try {
      final next = await page.nextPage();
      if (next != null) {
        _page = next;
        results.addAll(next.videos);
      }
    } catch (_) {
      // Ignore paging failures; user can scroll again.
    } finally {
      loadingMore.value = false;
    }
  }

  Future<void> pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) {
      Get.snackbar('Clipboard is empty', 'Copy a YouTube link first.',
          duration: const Duration(seconds: 2));
      return;
    }
    searchText.text = text;
    await submit(text);
  }

  void useHistory(String q) {
    searchText.text = q;
    submit(q);
  }

  void clearHistory() {
    history.clear();
    _storage.remove(AppConstants.kSearchHistory);
  }

  /// Leaves search mode and returns to the home feed.
  void clearResults() {
    searching.value = false;
    searchQuery.value = '';
    results.clear();
    error.value = null;
    _page = null;
  }

  void closeSearch() {
    searchText.clear();
    FocusManager.instance.primaryFocus?.unfocus();
    clearResults();
  }

  void _remember(String q) {
    history
      ..remove(q)
      ..insert(0, q);
    if (history.length > 12) history.removeRange(12, history.length);
    _storage.write(AppConstants.kSearchHistory, history.toList());
    _feedCache.remove(0); // "For you" follows history
  }

  // ---------------------------------------------------------------- formats

  /// yt-dlp info of the video in the sheet (formats + stream URLs).
  YtInfo? _info;

  /// Fast-path info of the video in the sheet (its audio URL plays at once).
  YtInfo? _quick;

  /// Search results when the bubble's "now playing" info isn't a clear
  /// match; the sheet asks the user to pick one.
  final candidates = <Video>[].obs;

  Future<void> openVideo(String videoId, {Video? known}) async {
    selectedVideo.value = known == null ? null : VideoMeta.fromVideo(known);
    _resetSheet();
    _showSheet();
    await _loadFormats(videoId);
  }

  /// The sheet led to a download / playback (its yt-dlp lookup is needed).
  bool _sheetUsed = false;

  void _showSheet() {
    _sheetUsed = false;
    Get.bottomSheet(const FormatSheet(), isScrollControlled: true).then((_) {
      // Closed without downloading or playing: stop the yt-dlp lookup still
      // running for it (Python + JS solving keep a CPU core busy).
      final id = _loadingId;
      if (!_sheetUsed && id != null && id.isNotEmpty) {
        YtDlpService.to.cancelInfo('https://www.youtube.com/watch?v=$id');
      }
    });
  }

  /// Bubble over the YouTube app: YouTube's media session told us what is
  /// playing. Open the sheet right away, then find the exact video.
  Future<void> openPlaying({
    required String title,
    String? artist,
    Duration? duration,
    String? mediaId,
  }) async {
    if (mediaId != null && RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(mediaId)) {
      return openVideo(mediaId);
    }
    selectedVideo.value = VideoMeta(
      id: '',
      title: title,
      author: artist ?? '',
      thumbnailUrl: '',
      duration: duration,
    );
    _resetSheet();
    formatsStatus.value = 'Finding the video…';
    _loadingId = null;
    _showSheet();
    try {
      final query = [title, if (artist != null && artist.isNotEmpty) artist].join(' ');
      final results = (await _yt.search(query)).videos.take(8).toList();
      final scores = [
        for (final v in results)
          VideoMatcher.score(
            title: v.title,
            author: v.author,
            duration: v.duration,
            targetTitle: title,
            targetAuthor: artist,
            targetDuration: duration,
          ),
      ];
      final winner = VideoMatcher.clearWinner(scores);
      if (winner != null) {
        selectedVideo.value = VideoMeta.fromVideo(results[winner]);
        await _loadFormats(results[winner].id.value);
        return;
      }
      final ranked = [for (var i = 0; i < results.length; i++) i]
        ..sort((a, b) => scores[b].compareTo(scores[a]));
      candidates.assignAll(ranked.take(4).map((i) => results[i]));
      if (candidates.isEmpty) {
        formatsError.value = 'Couldn\'t find this video. In YouTube, tap Share → "Download with Toomu".';
      }
    } catch (e) {
      debugPrint('[YouTube] finding "$title" failed: $e');
      formatsError.value = ErrorText.of(e);
    } finally {
      if (candidates.isNotEmpty || formatsError.value != null) {
        formatsLoading.value = false;
        formatsStatus.value = '';
      }
    }
  }

  /// User picked one of [candidates] in the sheet.
  Future<void> pickCandidate(Video video) async {
    candidates.clear();
    selectedVideo.value = VideoMeta.fromVideo(video);
    await _loadFormats(video.id.value);
  }

  void _resetSheet() {
    _info = null;
    _quick = null;
    candidates.clear();
    formatsLoading.value = true;
    formatsError.value = null;
    formatsStatus.value = '';
    videoFormats.clear();
    audioFormats.clear();
  }

  /// Fills the sheet as fast as possible: a lightweight quality list
  /// (~0.3 s, no yt-dlp) races the full yt-dlp info; the first good answer
  /// wins. yt-dlp keeps running in the background for "Play audio" and is
  /// cached, so downloads/reopening reuse it.
  Future<void> _loadFormats(String videoId) async {
    _loadingId = videoId;
    formatsLoading.value = true;
    formatsError.value = null;
    final ytdlp = YtDlpService.to;
    final url = 'https://www.youtube.com/watch?v=$videoId';
    final sw = Stopwatch()..start();

    // Instant when yt-dlp already looked at this video recently.
    final cached = ytdlp.cachedInfo(url);
    if (cached != null) {
      _info = cached;
      _show(cached, from: 'cache', ms: 0);
      formatsLoading.value = false;
      return;
    }

    formatsStatus.value = !ytdlp.ready.value
        ? 'Preparing downloader (first run)…'
        : ytdlp.updating.value
            ? 'Updating downloader…'
            : '';

    // Header for links whose title we don't know yet (fast, parallel).
    if (selectedVideo.value == null || selectedVideo.value!.id.isEmpty) {
      unawaited(_yt.video(videoId).then((v) {
        if (selectedVideo.value == null || selectedVideo.value!.id.isEmpty) {
          selectedVideo.value = VideoMeta.fromVideo(v);
        }
      }).catchError((Object _) {}));
    }

    final shown = Completer<void>();
    Object? ytdlpError;

    final full = ytdlp.info(url).timeout(const Duration(seconds: 90)).then((info) {
      if (_sheetVideoId != videoId) return;
      _info = info;
      final meta = selectedVideo.value;
      if (meta == null || meta.id.isEmpty) selectedVideo.value = VideoMeta.fromInfo(info);
      if (!shown.isCompleted) {
        _show(info, from: 'yt-dlp', ms: sw.elapsedMilliseconds);
        shown.complete();
      }
    }).catchError((Object e) {
      if (e is YtDlpCanceled) return; // sheet closed
      ytdlpError = e;
      debugPrint('[YouTube] yt-dlp formats for $videoId failed: $e');
    });

    final quick = _yt
        .quickInfo(videoId, duration: selectedVideo.value?.duration)
        .then((info) {
      if (info != null && _sheetVideoId == videoId) _quick = info;
      if (info == null || shown.isCompleted || _sheetVideoId != videoId) return;
      if (MediaFormat.videoOptions(info).isEmpty && MediaFormat.audioOptions(info).isEmpty) return;
      _show(info, from: 'quick list', ms: sw.elapsedMilliseconds);
      shown.complete();
    }).catchError((Object _) {});

    // Done when one path showed formats, or both finished without.
    await Future.any([shown.future, Future.wait([full, quick])]);
    if (!shown.isCompleted && _sheetVideoId == videoId) {
      formatsError.value = ytdlpError != null
          ? ErrorText.of(ytdlpError!)
          : 'No downloadable formats found for this video.';
    }
    formatsLoading.value = false;
    formatsStatus.value = '';
  }

  /// Which video the sheet currently shows (ignore late results for others).
  String? get _sheetVideoId => _loadingId;
  String? _loadingId;

  void _show(YtInfo info, {required String from, required int ms}) {
    videoFormats.assignAll(MediaFormat.videoOptions(info));
    audioFormats.assignAll(MediaFormat.audioOptions(info));
    formatsLoading.value = false;
    formatsStatus.value = '';
    debugPrint('[YouTube] formats from $from in $ms ms');
  }


  Future<void> download(MediaFormat format) async {
    final video = selectedVideo.value;
    if (video == null) return;
    _sheetUsed = true;
    await DownloadService.to.enqueue(video: video, format: format);
    Get.back();
    Get.snackbar('Download started', video.title, duration: const Duration(seconds: 2));
  }

  /// Watch in our own video player — YouTube's media streams themselves, so
  /// no ads. Uses the sheet's yt-dlp lookup (usually done by now).
  Future<void> watchVideo() async {
    final video = selectedVideo.value;
    if (video == null || video.id.isEmpty) return;
    _sheetUsed = true;
    openingVideo.value = true;
    await _watch(video.id, video.title, info: _info, duration: video.duration, beforeOpen: () {
      openingVideo.value = false;
      Get.back(); // the sheet
    });
    openingVideo.value = false;
  }

  /// Video card ▶ button: straight to the player, no sheet. The card shows
  /// a spinner while the streams are looked up.
  final watchingId = RxnString();

  Future<void> watchFromCard(Video video) async {
    if (watchingId.value != null) return; // one at a time
    watchingId.value = video.id.value;
    await _watch(video.id.value, video.title,
        duration: video.duration, beforeOpen: () => watchingId.value = null);
    watchingId.value = null;
  }

  /// Opens the player as fast as possible: yt-dlp's links when it already
  /// has them; otherwise the fast lookup's (~0.5 s) while yt-dlp looks the
  /// video up in the background — the player switches to yt-dlp's links
  /// only if YouTube cuts the fast ones off.
  Future<void> _watch(
    String id,
    String title, {
    YtInfo? info,
    Duration? duration,
    required VoidCallback beforeOpen,
  }) async {
    final sw = Stopwatch()..start();
    try {
      final ytdlp = YtDlpService.to;
      final url = 'https://www.youtube.com/watch?v=$id';
      final preferred = _storage.read<int>(AppConstants.kStreamQuality);
      VideoItem? item;
      var source = 'yt-dlp';

      final reliable = info ?? ytdlp.cachedInfo(url);
      if (reliable != null) {
        item = YoutubeStream.pick(reliable, videoId: id, title: title, preferred: preferred);
      } else {
        // Backup links, ready by the time they'd be needed.
        unawaited(ytdlp.info(url).then<void>((_) {}, onError: (Object _) {}));
        // Only links YouTube is actually serving (each client is checked).
        final fast = await _yt
            .playableInfo(id, duration: duration)
            .timeout(const Duration(seconds: 15), onTimeout: () => null)
            .catchError((Object _) => null);
        if (fast != null) {
          item = YoutubeStream.pick(fast.info, videoId: id, title: title, preferred: preferred, provisional: true);
          source = 'fast lookup (${fast.client})';
        } else {
          debugPrint('[YouTube] no fast links work right now; waiting for yt-dlp');
        }
        if (item == null) {
          item = YoutubeStream.pick(await ytdlp.info(url).timeout(const Duration(seconds: 90)),
              videoId: id, title: title, preferred: preferred);
          source = 'yt-dlp';
        }
      }
      if (item == null) throw StateError('No playable stream found for this video.');
      debugPrint('[YouTube] watching ${item.quality ?? '?'}'
          '${item.audioUri != null ? ' + separate audio' : ''} from $source after ${sw.elapsedMilliseconds} ms');
      beforeOpen();
      await Get.toNamed(Routes.videoPlayer, arguments: VideoPlaylist([item], 0));
    } catch (e) {
      debugPrint('[YouTube] watch failed: $e');
      Get.snackbar('Can\'t play this video', ErrorText.of(e));
    }
  }


  /// Stream the audio in the music player without downloading.
  ///
  /// Starts at once with the fast path's audio URL; yt-dlp (already running
  /// for the sheet) is the safety net — if YouTube refuses or cuts off the
  /// fast stream, playback switches to yt-dlp's URL at the same position.
  Future<void> playAudio() async {
    final video = selectedVideo.value;
    if (video == null) return;
    _sheetUsed = true;
    streamingAudio.value = true;
    final sw = Stopwatch()..start();
    final audio = AudioPlayerService.to;
    final trackId = 'yt:${video.id}';
    final ytdlpInfo = YtDlpService.to.info(video.watchUrl); // shared / cached run

    Track trackFor(YtFormat f) => Track(
          id: trackId,
          title: video.title,
          album: 'YouTube',
          uri: f.url!,
          duration: video.duration,
          artworkUrl: 'https://i.ytimg.com/vi/${video.id}/hqdefault.jpg',
          sourceBuilder: (item) =>
              AudioSource.uri(Uri.parse(f.url!), headers: f.httpHeaders.isEmpty ? null : f.httpHeaders, tag: item),
        );

    Future<bool> playFromYtDlp({Duration? at}) async {
      final best = (await ytdlpInfo).bestAudio;
      if (best?.url == null) throw StateError('No playable audio found.');
      return audio.playTracks([trackFor(best!)], position: at);
    }

    try {
      // 1. yt-dlp already done (recently opened) → its URL, no fallback needed.
      final done = _info ?? YtDlpService.to.cachedInfo(video.watchUrl);
      if (done?.bestAudio?.url != null) {
        await audio.playTracks([trackFor(done!.bestAudio!)]);
        Get.back();
        return;
      }

      // 2. Fast path (usually already fetched by the sheet).
      final quick = _quick ??
          await _yt
              .quickInfo(video.id, duration: video.duration)
              .timeout(const Duration(seconds: 4), onTimeout: () => null)
              .catchError((Object _) => null);
      final fast = quick?.bestAudio;
      if (fast?.url != null && await audio.playTracks([trackFor(fast!)], quiet: true)) {
        debugPrint('[YouTube] audio playing via fast path in ${sw.elapsedMilliseconds} ms');
        Get.back();
        _fallBackOnError(trackId, () async {
          final at = audio.position.value;
          debugPrint('[YouTube] fast audio stream failed at $at; switching to yt-dlp');
          await playFromYtDlp(at: at);
        });
        return;
      }

      // 3. No fast URL (or it failed to load) → yt-dlp.
      await playFromYtDlp();
      debugPrint('[YouTube] audio playing via yt-dlp in ${sw.elapsedMilliseconds} ms');
      Get.back();
    } catch (e) {
      Get.snackbar('Playback error', ErrorText.of(e));
    } finally {
      streamingAudio.value = false;
    }
  }

  /// Runs [fallback] once if [trackId] fails while it's still the current
  /// track (stops watching when something else plays).
  void _fallBackOnError(String trackId, Future<void> Function() fallback) {
    final audio = AudioPlayerService.to;
    late final StreamSubscription<String> errors;
    late final Worker trackWatch;
    void done() {
      errors.cancel();
      trackWatch.dispose();
    }

    errors = audio.trackErrors.where((id) => id == trackId).listen((_) {
      done();
      fallback().catchError((Object e) => Get.snackbar('Playback error', ErrorText.of(e)));
    });
    trackWatch = ever(audio.currentIndex, (_) {
      if (audio.current?.id != trackId) done();
    });
  }

}
