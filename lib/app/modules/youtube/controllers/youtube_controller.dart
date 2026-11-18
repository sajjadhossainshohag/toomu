import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:share_plus/share_plus.dart';
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
import '../../../data/repositories/feed_repository.dart';
import '../../../services/stream_proxy.dart';
import '../../../services/tiktok_service.dart';
import '../../home/controllers/home_controller.dart';
import '../../../services/youtube_account_service.dart';
import '../../../data/providers/youtube/account_feed.dart';
import '../../../data/providers/youtube/feed_mix.dart';
import '../../settings/views/youtube_sign_in_page.dart';
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
import '../../channel/controllers/channel_controller.dart';
import '../../shorts/controllers/shorts_controller.dart';
import '../../home/home_tabs.dart';
import '../../../data/models/download_task.dart';
import '../../../data/models/saved_videos.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/option_sheet.dart';
import '../../../widgets/app_snackbar.dart';

/// A home-feed category: searches (signed out — YouTube has no public
/// "trending" API), or one of the signed-in account's own feeds.
class FeedCategory {
  const FeedCategory(this.label, this.queries, this.icon, {this.load});

  final String label;

  /// Searches this tab mixes, a few picked at random per load. Empty =
  /// "For you": a random mix of every tab's searches, more topics and
  /// the user's recent searches (see [FeedMix]).
  final List<String> queries;
  final IconData icon;

  /// Signed in: loads the account's feed instead of searching.
  final Future<FeedPage?> Function()? load;
}

class YoutubeController extends GetxController {
  /// [random], [search] and [account] are for tests (deterministic picks,
  /// no network).
  YoutubeController({
    Random? random,
    Future<FeedPage> Function(String query)? search,
    AccountFeed? account,
  }) : _random = random ?? Random(),
       _searchOverride = search,
       _accountOverride = account;

  final Random _random;
  final Future<FeedPage> Function(String query)? _searchOverride;
  final AccountFeed? _accountOverride;

  final YoutubeProvider _yt = YoutubeProvider();
  WatchSource get watchSource => _yt;
  ChannelSource get channelSource => _yt;

  Future<FeedPage> _search(String query) =>
      _searchOverride?.call(query) ?? _yt.search(query);
  final _storage = StorageService.to;

  final searchText = TextEditingController();
  final history = <String>[].obs;

  // ---- Search mode (user typed a query) ---------------------------------
  final searching = false.obs;
  final searchFocused = false.obs;
  final searchQuery = ''.obs;
  final results = <Video>[].obs;
  final loading = false.obs;
  final loadingMore = false.obs;
  final error = RxnString();
  VideoPage? _page;

  // ---- Home feed ---------------------------------------------------------
  static const _builtInCategories = <FeedCategory>[
    FeedCategory('For you', [], Icons.auto_awesome_rounded),
    FeedCategory('Music', [
      'new music video',
      'official music video',
      'live music performance',
      'acoustic cover songs',
      'music video premiere this week',
    ], Icons.music_note_rounded),
    FeedCategory('Trending', [
      'trending videos today',
      'viral videos this week',
      'most viewed videos this week',
      'new videos today',
    ], Icons.local_fire_department_rounded),
    FeedCategory('Gaming', [
      'gaming highlights',
      'new game trailers',
      'gameplay walkthrough',
      'funny gaming moments',
    ], Icons.sports_esports_rounded),
    FeedCategory('News', [
      'news today',
      'world news this week',
      'tech news',
      'business news today',
    ], Icons.newspaper_rounded),
    FeedCategory('Sports', [
      'sports highlights',
      'football highlights',
      'cricket highlights',
      'basketball highlights',
    ], Icons.sports_soccer_rounded),
    FeedCategory('Podcasts', [
      'podcast full episode',
      'interview podcast',
      'comedy podcast',
      'science podcast',
    ], Icons.podcasts_rounded),
    FeedCategory('Comedy', [
      'funny videos',
      'stand up comedy',
      'comedy sketches',
      'try not to laugh',
    ], Icons.sentiment_very_satisfied_rounded),
  ];

  /// Signed out: "For you" first; the rest from remote config when
  /// provided.
  static List<FeedCategory> get _searchCategories {
    final remote = RemoteConfigService.to.feedCategories;
    if (remote.isEmpty) return _builtInCategories;
    return [
      _builtInCategories.first,
      for (final c in remote)
        FeedCategory(c.label, c.queries, Icons.label_rounded),
    ];
  }

  /// How many of a tab's searches one load mixes.
  static const _queriesPerCategory = 2;

  /// The searches of one feed load: a few of the tab's own, or for
  /// "For you" a fresh random mix (not the one shown last time).
  List<String> _feedQueries(FeedCategory? category) {
    final own = category?.queries ?? const <String>[];
    if (own.isNotEmpty) {
      return ([...own]..shuffle(_random)).take(_queriesPerCategory).toList();
    }
    final topics = FeedMix.pickTopics(
      pool: {
        for (final c in _searchCategories) ...c.queries,
        for (final c in _builtInCategories) ...c.queries,
        ...FeedMix.extraTopics,
      },
      history: history,
      avoid: (_storage.read<List>(AppConstants.kFeedTopics) ?? const [])
          .whereType<String>(),
      random: _random,
    );
    unawaited(_storage.write(AppConstants.kFeedTopics, topics));
    return topics;
  }

  /// The feed's categories: the search-based ones, or — signed in to
  /// YouTube — Home, Subscriptions and the account's own categories.
  final categories = <FeedCategory>[].obs;

  late final AccountFeed _account =
      _accountOverride ?? AccountFeed(YoutubeAccountService.to.cookies);

  List<FeedCategory> get _accountCategories => [
    FeedCategory('Home', const [], Icons.home_rounded, load: _accountHome),
    FeedCategory(
      'Subscriptions',
      const [],
      Icons.subscriptions_rounded,
      load: _account.subscriptions,
    ),
  ];

  /// The account's Home; its first answer also brings the account's
  /// categories. No recommendations (watch history off) or failing
  /// (offline, expired sign-in, YouTube changed its page) → the varied
  /// search-based feed instead; pull to refresh tries the account again.
  Future<FeedPage?> _accountHome() async {
    AccountFeedPage? home;
    Object? failure;
    try {
      home = await _account.home();
      if (home == null) {
        debugPrint('[YouTube] account home is empty (watch history off?); using the regular feed');
      }
    } catch (e) {
      failure = e;
      debugPrint('[YouTube] account home failed ($e); using the regular feed');
    }
    if (home == null) {
      // Say why their own feed isn't there, and what helps.
      feedNotice.value = accountHomeNotice(failure);
      await _useSearchFeed();
      return null;
    }
    feedNotice.value = null;
    if (home.chips.isNotEmpty && categories.length <= 2) {
      categories.addAll([
        for (final c in home.chips)
          FeedCategory(
            c.label,
            const [],
            Icons.label_rounded,
            load: () => _account.chip(c),
          ),
      ]);
    }
    return home;
  }

  bool _searchFallback = false;

  /// Signed in but shown the general feed: why, and what to do.
  final feedNotice = Rxn<HomeFeedNotice>();

  /// The notice's button: try the account's home again, or sign in again
  /// (the saved session expired; sign-in stays "on", so nothing else
  /// would start the feed over).
  Future<void> onFeedNotice() async {
    final notice = feedNotice.value;
    if (notice == null) return;
    if (notice.action == HomeFeedAction.signIn && !await YoutubeSignInPage.open()) return;
    feedNotice.value = null;
    _searchFallback = false;
    await _resetFeed();
  }

  Future<void> _useSearchFeed() {
    _searchFallback = true;
    return _resetFeed();
  }

  /// Signed in/out: start the feed over with the matching categories.
  Future<void> _resetFeed() {
    _feedCache.clear();
    _feedPage = null;
    feed.clear();
    feedIndex.value = 0;
    final account = YoutubeAccountService.to.signedIn.value && !_searchFallback;
    categories.assignAll(account ? _accountCategories : _searchCategories);
    return loadFeed();
  }

  final feedIndex = 0.obs;
  final feed = <Video>[].obs;
  final feedLoading = false.obs;
  final feedLoadingMore = false.obs;
  final feedError = RxnString();
  FeedPage? _feedPage;
  final Map<int, ({List<Video> items, FeedPage? page})> _feedCache = {};
  late final FeedRepository _feedStore = FeedRepository(_storage);

  String get _feedStoreKey {
    final first = categories.isEmpty ? null : categories.first;
    return first?.load != null ? 'account:${first!.label}' : 'search:${first?.label}';
  }

  Worker? _signInWatch;

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
    _yt.warmUp(); // visitor id for the fast lookup, before the first tap
    final account = YoutubeAccountService.to;
    categories.assignAll(
      account.signedIn.value ? _accountCategories : _searchCategories,
    );
    _signInWatch = ever(account.signedIn, (_) {
      _searchFallback = false;
      feedNotice.value = null;
      unawaited(_resetFeed());
    });
    history.assignAll(
      (_storage.read<List>(AppConstants.kSearchHistory) ?? const [])
          .cast<String>(),
    );
    watched.assignAll(SavedVideos.read(_storage.read<List>(AppConstants.kWatchHistory)));
    watchLater.assignAll(SavedVideos.read(_storage.read<List>(AppConstants.kWatchLater)));
  }

  final watched = <Video>[].obs;
  final watchLater = <Video>[].obs;

  void _rememberWatched(Video video) {
    watched.assignAll(SavedVideos.add(watched, video));
    unawaited(_storage.write(AppConstants.kWatchHistory, SavedVideos.write(watched)));
  }

  void removeWatched(Video video) {
    watched.removeWhere((v) => v.id == video.id);
    unawaited(_storage.write(AppConstants.kWatchHistory, SavedVideos.write(watched)));
  }

  void clearWatched() {
    watched.clear();
    unawaited(_storage.remove(AppConstants.kWatchHistory));
  }

  bool isSaved(Video video) => watchLater.any((v) => v.id == video.id);

  void toggleWatchLater(Video video) {
    if (isSaved(video)) {
      watchLater.removeWhere((v) => v.id == video.id);
      showSnack('Removed from Watch later', video.title, duration: const Duration(seconds: 2));
    } else {
      watchLater.assignAll(SavedVideos.add(watchLater, video));
      showSnack('Saved to Watch later', video.title, duration: const Duration(seconds: 2));
    }
    unawaited(_storage.write(AppConstants.kWatchLater, SavedVideos.write(watchLater)));
  }

  @override
  void onReady() {
    super.onReady();
    final saved = _feedStore.load(_feedStoreKey);
    if (saved != null && feed.isEmpty) feed.assignAll(saved);
    // The saved feed stays where it is (the user may already be reading or
    // tapping it); the fresh mix goes below it.
    loadFeed(refresh: saved != null, keepShown: saved != null);
  }

  @override
  void onClose() {
    _signInWatch?.dispose();
    searchText.dispose();
    _yt.dispose();
    super.onClose();
  }

  // ------------------------------------------------------------------- feed

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

  /// [keepShown]: add the new videos after the ones on screen instead of
  /// replacing them (the launch, over the saved feed).
  Future<void> loadFeed({bool refresh = false, bool keepShown = false}) async {
    final index = feedIndex.value;
    // Signed in but showing the fallback: refreshing tries the account again.
    if (refresh &&
        index == 0 &&
        _searchFallback &&
        YoutubeAccountService.to.signedIn.value) {
      _searchFallback = false;
      return _resetFeed();
    }
    if (refresh) _feedCache.remove(index);
    feedLoading.value = !refresh || feed.isEmpty;
    feedError.value = null;
    final category = index < categories.length ? categories[index] : null;
    try {
      final load = category?.load;
      final FeedPage? page = load != null
          ? await load()
          : await MixedFeedPage.load(_feedQueries(category), _search);
      if (page == null ||
          index != feedIndex.value ||
          !identical(category, categories.elementAtOrNull(index))) {
        return; // fell back, or the user switched meanwhile
      }
      _feedPage = page;
      final fresh = _downloadable(page.videos).toList();
      if (keepShown && feed.isNotEmpty) {
        feed.addAll(_notShown(fresh));
      } else {
        feed.assignAll(fresh);
      }
      _feedCache[index] = (items: feed.toList(), page: page);
      // Next launch opens on this mix, not the one before.
      if (index == 0) unawaited(_feedStore.save(_feedStoreKey, fresh));
    } catch (e) {
      debugPrint('[YouTube] feed failed: $e');
      if (index == feedIndex.value) feedError.value = ErrorText.of(e);
    } finally {
      // Not when the feed was started over meanwhile (that load owns it).
      if (index == feedIndex.value &&
          identical(category, categories.elementAtOrNull(index))) {
        feedLoading.value = false;
      }
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
        feed.addAll(_notShown(_downloadable(next.videos)));
        _feedCache[index] = (items: feed.toList(), page: next);
      }
    } catch (_) {
      // Ignore paging failures; user can scroll again.
    } finally {
      feedLoadingMore.value = false;
    }
  }

  /// [videos] not already in the feed (a page after the saved one at launch
  /// can bring the same videos again).
  Iterable<Video> _notShown(Iterable<Video> videos) {
    final shown = {for (final v in feed) v.id.value};
    return videos.where((v) => shown.add(v.id.value));
  }

  void trimFeedCache() => _feedCache.removeWhere((i, _) => i != feedIndex.value);

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
    final list = LinkParser.youtubeCollection(text);
    if (list != null) return openCollection(list);
    // A TikTok link: downloaded as is (no watermark).
    if (TiktokService.linkIn(text) != null) {
      await Get.find<HomeController>().openLinkFrom(text);
      return;
    }
    // 1DM-style: any direct file link downloads as-is.
    final uri = Uri.tryParse(text);
    if (uri != null && const DirectFileExtractor().canHandle(uri)) {
      return DirectFileExtractor.startDownload(text);
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
      showSnack(
        'Clipboard is empty',
        'Copy a YouTube link first.',
        duration: const Duration(seconds: 2),
      );
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
    _feedCache.remove(0); // "For you" mixes in the history
  }

  // ---------------------------------------------------------------- formats

  /// yt-dlp info of the video in the sheet (formats + stream URLs).
  YtInfo? _info;

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
      final query = [
        title,
        if (artist != null && artist.isNotEmpty) artist,
      ].join(' ');
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
        formatsError.value =
            'Couldn\'t find this video. In YouTube, tap Share → "Download with Toomu".';
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
    candidates.clear();
    formatsLoading.value = true;
    formatsError.value = null;
    formatsStatus.value = '';
    videoFormats.clear();
    audioFormats.clear();
  }

  /// Fills the sheet as fast as possible from the fast lookup (~0.4 s, no
  /// yt-dlp); yt-dlp is only started when those links don't cover whole
  /// files, or the fast lookup is slow or fails.
  Future<void> _loadFormats(String videoId) async {
    _loadingId = videoId;
    formatsLoading.value = true;
    formatsError.value = null;
    needsSignIn.value = false;
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
      unawaited(
        _yt
            .video(videoId)
            .then((v) {
              if (selectedVideo.value == null ||
                  selectedVideo.value!.id.isEmpty) {
                selectedVideo.value = VideoMeta.fromVideo(v);
              }
            })
            .catchError((Object _) {}),
      );
    }

    final shown = Completer<void>();
    void showFast(FastLinks? fast) {
      if (fast == null || shown.isCompleted || _sheetVideoId != videoId) return;
      if (MediaFormat.videoOptions(fast.info).isEmpty &&
          MediaFormat.audioOptions(fast.info).isEmpty) {
        return;
      }
      _show(
        fast.info,
        from: 'fast lookup (${fast.client})',
        ms: sw.elapsedMilliseconds,
      );
      shown.complete();
    }

    // The fast lookup gets a head start. With whole-file links (visionOS)
    // it's all the sheet needs — downloads, Watch and Play audio use those
    // links — so yt-dlp isn't started at all: one Python run (CPU, heat)
    // saved per video.
    final fastLookup = _yt
        .fastLinks(videoId, duration: selectedVideo.value?.duration)
        .timeout(const Duration(seconds: 12), onTimeout: () => null)
        .catchError((Object _) => null);
    final early = await Future.any<FastLinks?>([
      fastLookup,
      Future<FastLinks?>.delayed(const Duration(seconds: 3), () => null),
    ]);
    if (_sheetVideoId != videoId) return;
    showFast(early);
    if (early != null && early.full && shown.isCompleted) return;

    // Otherwise yt-dlp too (its links are needed, or the fast lookup is
    // slow / failed): the first good answer fills the sheet.
    Object? ytdlpError;
    final full = ytdlp
        .info(url)
        .timeout(const Duration(seconds: 90))
        .then((info) {
          if (_sheetVideoId != videoId) return;
          _info = info;
          final meta = selectedVideo.value;
          if (meta == null || meta.id.isEmpty) {
            selectedVideo.value = VideoMeta.fromInfo(info);
          }
          if (!shown.isCompleted) {
            _show(info, from: 'yt-dlp', ms: sw.elapsedMilliseconds);
            shown.complete();
          }
        })
        .catchError((Object e) {
          if (e is YtDlpCanceled) return; // sheet closed
          ytdlpError = e;
          debugPrint('[YouTube] yt-dlp formats for $videoId failed: $e');
        });
    final quick = fastLookup.then(showFast);

    // Done when one path showed formats, or both finished without.
    await Future.any([
      shown.future,
      Future.wait([full, quick]),
    ]);
    if (!shown.isCompleted && _sheetVideoId == videoId) {
      formatsError.value = ytdlpError != null
          ? ErrorText.of(ytdlpError!)
          : 'No downloadable formats found for this video.';
      needsSignIn.value = _wantsSignIn(ytdlpError);
    }
    formatsLoading.value = false;
    formatsStatus.value = '';
  }

  /// The sheet's error is YouTube asking for a sign-in (age-restricted).
  final needsSignIn = false.obs;

  static bool _wantsSignIn(Object? e) {
    if (YoutubeAccountService.to.signedIn.value) return false;
    final text = e is YtDlpException ? e.message : '$e';
    return YtDlpService.isAgeRestricted(text) ||
        YtDlpService.isSessionExpired(text);
  }

  /// Sheet button: sign in, then look the video up again.
  Future<void> signInAndRetry() async {
    final id = _loadingId;
    if (id == null || !await YoutubeSignInPage.open() || _loadingId != id) {
      return;
    }
    _resetSheet();
    await _loadFormats(id);
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

  bool _listLoading = false;

  Future<void> openCollection(String url) async {
    if (_listLoading) return;
    _listLoading = true;
    showSnack('Getting the list…', 'Long playlists take a few seconds.', duration: const Duration(minutes: 2));
    try {
      final list = await YtDlpService.to.collection(url).timeout(const Duration(minutes: 2));
      Get.closeAllSnackbars();
      if (list.videos.isEmpty) {
        showSnack('Nothing to download', 'This list has no videos that can be downloaded.');
        return;
      }
      final count = list.videos.length;
      final format = await showOptionSheet<MediaFormat>(
        title: '${list.title} · $count ${count == 1 ? 'video' : 'videos'}',
        options: [
          for (final f in MediaFormat.listOptions())
            SheetOption(
              value: f,
              label: f.name,
              subtitle: f.detail,
              icon: f.kind == DownloadKind.audio ? Icons.music_note_rounded : Icons.movie_rounded,
            ),
        ],
      );
      if (format == null) return;
      final fresh = DownloadService.notYetQueued(list.videos, DownloadService.to.tasks, format.kind);
      if (fresh.isEmpty) {
        showSnack('Already in Downloads', 'Every video in this list is already there.');
        return;
      }
      final skipped = count - fresh.length;
      final ok = await showConfirmDialog(
        title: 'Download ${fresh.length} ${fresh.length == 1 ? 'video' : 'videos'}?',
        message: [
          '${list.title}, ${format.label}.',
          if (skipped > 0) '$skipped already in Downloads ${skipped == 1 ? 'is' : 'are'} skipped.',
          if (count >= YtDlpService.maxListVideos) 'Only the first ${YtDlpService.maxListVideos} videos are included.',
        ].join('\n'),
        confirmLabel: 'Download',
      );
      if (!ok) return;
      final added = await DownloadService.to.enqueueAll(fresh, format);
      Get.find<HomeController>().openTab(HomeTabs.downloads);
      showSnack('Downloads queued', '$added from ${list.title}', duration: const Duration(seconds: 3));
    } catch (e) {
      Get.closeAllSnackbars();
      debugPrint('[YouTube] list $url failed: $e');
      showSnack("Can't open this list", ErrorText.of(e));
    } finally {
      _listLoading = false;
    }
  }

  int get lastVideoQuality => _storage.read<int>(AppConstants.kDownloadQuality) ?? 1080;

  Future<void> download(MediaFormat format) async {
    final video = selectedVideo.value;
    if (video == null) return;
    _sheetUsed = true;
    if (format.kind == DownloadKind.video) unawaited(_storage.write(AppConstants.kDownloadQuality, format.height));
    await DownloadService.to.enqueue(video: video, format: format);
    Get.back();
    showSnack(
      'Download started',
      video.title,
      duration: const Duration(seconds: 2),
    );
  }

  /// Watch in our own video player — YouTube's media streams themselves, so
  /// no ads. Uses the sheet's yt-dlp lookup (usually done by now).
  Future<void> watchVideo() async {
    final video = selectedVideo.value;
    if (video == null || video.id.isEmpty) return;
    _sheetUsed = true;
    openingVideo.value = true;
    await _watch(
      video.id,
      video.title,
      info: _info,
      duration: video.duration,
      beforeOpen: () {
        openingVideo.value = false;
        Get.back(); // the sheet
      },
    );
    openingVideo.value = false;
  }

  /// Video card: straight to the player, no sheet. The card shows
  /// a spinner while the streams are looked up.
  final watchingId = RxnString();

  void prefetch(Video video) => _yt.fastLinks(video.id.value, duration: video.duration).ignore();

  Future<void> watchFromCard(Video video) async {
    if (watchingId.value != null) return; // one at a time
    watchingId.value = video.id.value;
    await _watch(
      video.id.value,
      video.title,
      duration: video.duration,
      beforeOpen: () {
        watchingId.value = null;
        _rememberWatched(video);
      },
    );
    watchingId.value = null;
  }

  Future<void> showVideoMenu(Video video) async {
    final pick = await showOptionSheet<String>(
      title: video.title,
      options: <SheetOption<String>>[
        const SheetOption(value: 'download', label: 'Download', icon: Icons.download_rounded),
        isSaved(video)
            ? const SheetOption(value: 'later', label: 'Remove from Watch later', icon: Icons.bookmark_remove_rounded)
            : const SheetOption(value: 'later', label: 'Save to Watch later', icon: Icons.bookmark_add_outlined),
        const SheetOption(value: 'channel', label: 'Go to channel', icon: Icons.account_circle_rounded),
        const SheetOption(value: 'share', label: 'Share', icon: Icons.share_rounded),
        const SheetOption(value: 'copy', label: 'Copy link', icon: Icons.link_rounded),
      ],
    );
    switch (pick) {
      case 'download':
        await openVideo(video.id.value, known: video);
      case 'later':
        toggleWatchLater(video);
      case 'channel':
        await openChannel(video);
      case 'share':
        await shareVideo(video);
      case 'copy':
        await copyLink(video);
    }
  }

  // From the watch page the channel takes the player's place: with one shared player and no video mini player,
  // a video left playing under it would be taken over by the channel's Shorts.
  Future<void> openChannel(Video video, {bool replace = false}) async {
    final ChannelArgs args = (id: video.channelId.value, title: video.author);
    if (replace) {
      await Get.offNamed<void>(Routes.channel, arguments: args);
    } else {
      await Get.toNamed<void>(Routes.channel, arguments: args);
    }
  }

  Future<void> openShorts(List<Video> videos, int index) async {
    final ShortsArgs args = (videos: videos, index: index);
    await Get.toNamed<void>(Routes.shorts, arguments: args);
  }

  static String linkOf(Video video) => 'https://youtu.be/${video.id.value}';

  Future<void> shareVideo(Video video) =>
      SharePlus.instance.share(ShareParams(text: linkOf(video), subject: video.title));

  Future<void> copyLink(Video video) async {
    await Clipboard.setData(ClipboardData(text: linkOf(video)));
    showSnack('Link copied', video.title, duration: const Duration(seconds: 2));
  }

  Future<void> watchInPlace(Video video) async {
    if (watchingId.value != null) return;
    watchingId.value = video.id.value;
    await _watch(
      video.id.value,
      video.title,
      duration: video.duration,
      replace: true,
      beforeOpen: () {
        watchingId.value = null;
        _rememberWatched(video);
      },
    );
    watchingId.value = null;
  }

  /// Opens the player as fast as possible: yt-dlp's links when it already
  /// has them; otherwise the fast lookup's (well under a second). Those
  /// are whole-file links (visionOS client) — or, when only the Android
  /// client works, links for about the first minute that the stream proxy
  /// extends with yt-dlp's links, looked up while the video plays.
  Future<void> _watch(
    String id,
    String title, {
    YtInfo? info,
    Duration? duration,
    bool replace = false,
    required VoidCallback beforeOpen,
  }) async {
    try {
      final item = await resolveStream(id, title, info: info, duration: duration);
      beforeOpen();
      final args = VideoPlaylist([item], 0);
      if (replace) {
        // From the watch page's Up next: the next video takes this player's place instead of stacking a second one.
        await Get.offNamed<void>(Routes.videoPlayer, arguments: args);
      } else {
        await Get.toNamed<void>(Routes.videoPlayer, arguments: args);
      }
    } catch (e) {
      debugPrint('[YouTube] watch failed: $e');
      showSnack(
        'Can\'t play this video',
        ErrorText.of(e),
        mainButton: _wantsSignIn(e)
            ? TextButton(
                onPressed: () => YoutubeSignInPage.open(),
                child: const Text('Sign in'),
              )
            : null,
      );
    }
  }

  Future<VideoItem> resolveStream(String id, String title, {YtInfo? info, Duration? duration}) async {
    final sw = Stopwatch()..start();
    {
      final ytdlp = YtDlpService.to;
      final url = 'https://www.youtube.com/watch?v=$id';
      final preferred = _storage.read<int>(AppConstants.kStreamQuality);
      VideoItem? item;
      var source = 'yt-dlp';

      final reliable = info ?? ytdlp.cachedInfo(url);
      if (reliable != null) {
        item = YoutubeStream.pick(
          reliable,
          videoId: id,
          title: title,
          preferred: preferred,
        );
      } else {
        final fast = await _yt
            .fastLinks(id, duration: duration)
            .timeout(const Duration(seconds: 15), onTimeout: () => null)
            .catchError((Object _) => null);
        if (fast != null) {
          item = YoutubeStream.pick(
            fast.info,
            videoId: id,
            title: title,
            preferred: preferred,
            provisional: true,
            partial: !fast.full,
          );
          source =
              'fast lookup (${fast.client}${fast.full ? '' : ', first minute'})';
        } else {
          debugPrint(
            '[YouTube] no fast links work right now; waiting for yt-dlp',
          );
        }
        if (item == null) {
          item = YoutubeStream.pick(
            await ytdlp.info(url).timeout(const Duration(seconds: 90)),
            videoId: id,
            title: title,
            preferred: preferred,
          );
          source = 'yt-dlp';
        }
      }
      if (item == null) {
        throw StateError('No playable stream found for this video.');
      }
      debugPrint(
        '[YouTube] watching ${item.quality ?? '?'}'
        '${item.audioUri != null ? ' + separate audio' : ''} from $source after ${sw.elapsedMilliseconds} ms',
      );
      return item;
    }
  }

  /// Stream the audio in the music player without downloading.
  ///
  /// Starts at once with the fast lookup's audio link, played through the
  /// stream proxy; yt-dlp is the safety net — if the fast stream fails
  /// anyway, playback switches to yt-dlp's link at the same position.
  Future<void> playAudio() async {
    final video = selectedVideo.value;
    if (video == null) return;
    _sheetUsed = true;
    streamingAudio.value = true;
    final sw = Stopwatch()..start();
    final audio = AudioPlayerService.to;
    final trackId = 'yt:${video.id}';

    Track trackFor(YtFormat f, {bool partial = false}) {
      final link = StreamProxy.to.wrap(
        f.url!,
        headers: f.httpHeaders,
        videoId: video.id,
        partial: partial,
      );
      final direct = link == f.url;
      return Track(
        id: trackId,
        title: video.title,
        album: 'YouTube',
        uri: link,
        duration: video.duration,
        artworkUrl: 'https://i.ytimg.com/vi/${video.id}/hqdefault.jpg',
        sourceBuilder: (item) => AudioSource.uri(
          Uri.parse(link),
          headers: direct && f.httpHeaders.isNotEmpty ? f.httpHeaders : null,
          tag: item,
        ),
      );
    }

    // yt-dlp only when needed (shared with any lookup already running).
    Future<bool> playFromYtDlp({Duration? at}) async {
      final best = (await YtDlpService.to.info(video.watchUrl)).bestAudio;
      if (best?.url == null) throw StateError('No playable audio found.');
      return audio.playTracks([trackFor(best!)], position: at);
    }

    try {
      // 1. yt-dlp already done (recently opened) → its link, no fallback needed.
      final done = _info ?? YtDlpService.to.cachedInfo(video.watchUrl);
      if (done?.bestAudio?.url != null) {
        await audio.playTracks([trackFor(done!.bestAudio!)]);
        Get.back();
        return;
      }

      // 2. Fast lookup (usually already done by the sheet).
      final fast = await _yt
          .fastLinks(video.id, duration: video.duration)
          .timeout(const Duration(seconds: 6), onTimeout: () => null)
          .catchError((Object _) => null);
      final best = fast?.info.bestAudio;
      if (best?.url != null &&
          await audio.playTracks([
            trackFor(best!, partial: !fast!.full),
          ], quiet: true)) {
        debugPrint(
          '[YouTube] audio playing via fast lookup (${fast.client}) in ${sw.elapsedMilliseconds} ms',
        );
        Get.back();
        _fallBackOnError(trackId, () async {
          final at = audio.position.value;
          debugPrint(
            '[YouTube] fast audio stream failed at $at; switching to yt-dlp',
          );
          await playFromYtDlp(at: at);
        });
        return;
      }

      // 3. No fast link (or it failed to load) → yt-dlp.
      await playFromYtDlp();
      debugPrint(
        '[YouTube] audio playing via yt-dlp in ${sw.elapsedMilliseconds} ms',
      );
      Get.back();
    } catch (e) {
      showSnack('Playback error', ErrorText.of(e));
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
      fallback().catchError(
        (Object e) => showSnack('Playback error', ErrorText.of(e)),
      );
    });
    trackWatch = ever(audio.currentIndex, (_) {
      if (audio.current?.id != trackId) done();
    });
  }
}
