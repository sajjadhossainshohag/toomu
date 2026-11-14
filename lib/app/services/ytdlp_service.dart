import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

import '../core/values/app_constants.dart';
import '../data/models/yt_info.dart';
import '../core/utils/link_parser.dart';
import '../data/providers/youtube/po_token_service.dart';
import '../data/providers/ytdlp/ytdlp_bridge.dart';
import 'storage_service.dart';
import 'youtube_account_service.dart';

/// Owns the bundled yt-dlp: starts it, keeps it updated from GitHub (no
/// server of our own; Snaptube-style "hot update"), and builds the common
/// command-line options.
class YtDlpService extends GetxService {
  static YtDlpService get to => Get.find();

  final _storage = StorageService.to;

  final version = RxnString();
  final updating = false.obs;
  final ready = false.obs;
  final channel = 'stable'.obs; // or 'nightly'

  /// Extra yt-dlp args from remote config (e.g. extractor-args).
  final remoteArgs = <String>[].obs;

  final Completer<void> _ready = Completer<void>();
  String _cacheDir = '';

  /// Per-task folders for yt-dlp's intermediate files; empty until started.
  String workRoot = '';

  static const _updateEvery = Duration(hours: 24);

  /// Startup update; runs wait for it so they use the fresh yt-dlp and
  /// never race with the binary being replaced.
  Future<void>? _updateInFlight;

  Future<void> _waitForUpdate() async {
    final pending = _updateInFlight;
    if (pending == null) return;
    await pending.timeout(const Duration(seconds: 90), onTimeout: () {});
  }

  YtDlpService init() {
    channel.value = _storage.read<String>(AppConstants.kYtdlpChannel) ?? 'stable';
    unawaited(_start());
    return this;
  }

  /// Completes once yt-dlp is unpacked (first launch: a few seconds).
  Future<void> get whenReady => _ready.future;

  Future<void> _start() async {
    try {
      final tmp = await getTemporaryDirectory();
      _cacheDir = '${tmp.path}/ytdlp-cache';
      workRoot = '${tmp.path}/ytdlp-work';
      await Directory(workRoot).create(recursive: true);
      version.value = await YtDlpBridge.init();
      ready.value = true;
      if (!_ready.isCompleted) _ready.complete();
      debugPrint('[yt-dlp] ready ${version.value}');
      _updateInFlight = _autoUpdate();
    } catch (e) {
      debugPrint('[yt-dlp] init failed: $e');
      if (!_ready.isCompleted) _ready.completeError(e);
    }
  }

  /// Daily check (and on every launch until one succeeds). YouTube breaks
  /// things often; yt-dlp usually ships a fix within days, and this brings
  /// it in without an app update.
  Future<void> _autoUpdate() async {
    final last = _storage.read<int>(AppConstants.kYtdlpUpdatedAt) ?? 0;
    final due = DateTime.now().millisecondsSinceEpoch - last > _updateEvery.inMilliseconds;
    if (due) await update();
    _updateInFlight = null;
  }

  /// Returns a short status for the UI. Callers must not run while a
  /// download is active (Settings checks that).
  Future<String> update() async {
    if (updating.value) return 'Already updating';
    updating.value = true;
    try {
      await whenReady;
      debugPrint('[yt-dlp] checking for update (${channel.value})…');
      final status = await YtDlpBridge.update(channel.value);
      await _storage.write(AppConstants.kYtdlpUpdatedAt, DateTime.now().millisecondsSinceEpoch);
      version.value = await YtDlpBridge.version();
      debugPrint('[yt-dlp] update: $status → ${version.value}');
      return status == 'DONE' ? 'Updated to ${version.value}' : 'Already up to date (${version.value})';
    } catch (e) {
      debugPrint('[yt-dlp] update failed: $e');
      return 'Update failed: $e';
    } finally {
      updating.value = false;
    }
  }

  void setChannel(String value) {
    channel.value = value;
    _storage.write(AppConstants.kYtdlpChannel, value);
  }

  /// Options shared by every run.
  List<String> get baseArgs => [
        '--no-playlist',
        '--no-mtime',
        '--newline',
        // Give up on a dead connection instead of hanging (default 20 s,
        // retried several times).
        '--socket-timeout', '15',
        // IPv4 only: YouTube ties links to the IP version they were looked
        // up with (403 otherwise), and a half-working IPv6 makes every
        // connection wait out the timeout (yt-dlp doesn't fall back fast).
        '-4',
        '--cache-dir', _cacheDir, // caches YouTube player JS → faster
        // JS-challenge solver scripts if not bundled (yt-dlp ≥ 2025.11.12 only).
        if (_supportsRemoteComponents) ...['--remote-components', 'ejs:github'],
        ...remoteArgs,
      ];

  bool get _supportsRemoteComponents {
    final v = version.value;
    if (v == null) return false;
    final m = RegExp(r'(\d{4})\.(\d{1,2})\.(\d{1,2})').firstMatch(v);
    if (m == null) return false;
    final n = int.parse(m[1]!) * 10000 + int.parse(m[2]!) * 100 + int.parse(m[3]!);
    return n >= 20251112;
  }

  /// Recent info results; stream URLs inside stay valid for hours, so a
  /// reopened sheet / "Play audio" is instant.
  final Map<String, ({DateTime at, YtInfo info, String json})> _infoCache = {};
  final Map<String, Future<YtInfo>> _infoInFlight = {};
  final Map<String, String> _infoRunIds = {};
  final Set<String> _infoCanceled = {};
  static const _infoTtl = Duration(minutes: 30);

  /// Title, formats etc. of one video. Concurrent calls for the same URL
  /// share one yt-dlp run.
  Future<YtInfo> info(String url) {
    final cached = _infoCache[url];
    if (cached != null && DateTime.now().difference(cached.at) < _infoTtl) {
      return Future.value(cached.info);
    }
    // Block body on purpose: `=> _infoInFlight.remove(url)` would return the
    // removed future (this very one) and whenComplete would wait for it —
    // the lookup would never complete for anyone awaiting it.
    return _infoInFlight[url] ??= _fetchInfo(url).whenComplete(() {
      _infoInFlight.remove(url);
    });
  }

  /// Stops an unfinished lookup nobody needs any more (the sheet was
  /// closed without downloading or playing).
  void cancelInfo(String url) {
    if (!_infoInFlight.containsKey(url)) return;
    _infoCanceled.add(url);
    final id = _infoRunIds[url];
    if (id != null) YtDlpBridge.cancel(id);
    debugPrint('[yt-dlp] lookup stopped (sheet closed)');
  }

  /// The cached result only (null if none yet).
  YtInfo? cachedInfo(String url) {
    final cached = _infoCache[url];
    return cached != null && DateTime.now().difference(cached.at) < _infoTtl ? cached.info : null;
  }

  /// yt-dlp's raw info JSON for [url] if a lookup already finished (no
  /// waiting).
  String? savedInfoJson(String url) {
    final c = _infoCache[url];
    return c != null && DateTime.now().difference(c.at) < _infoTtl ? c.json : null;
  }

  /// yt-dlp's raw info JSON for [url], so a download can skip extraction
  /// (`--load-info-json`). Waits for an extraction already in progress (the
  /// format sheet may have started one); null if there is none.
  Future<String?> infoJsonFor(String url) async {
    String? fresh() => savedInfoJson(url);

    final cached = fresh();
    if (cached != null) return cached;
    final pending = _infoInFlight[url];
    if (pending == null) return null;
    // Waiting is cheaper than a second, parallel extraction (each one is
    // Python + JS solving): the lookup has its own time limits and gives
    // up on its own.
    try {
      await pending.timeout(const Duration(minutes: 3));
    } catch (_) {
      return null;
    }
    return fresh();
  }

  /// One run with no client fallback and no URL (e.g. `--load-info-json`).
  Future<YtDlpResult> runWithoutUrl(String id, List<String> args, {void Function(String line)? onLine}) async {
    await whenReady;
    await _waitForUpdate();
    final r = await YtDlpBridge.run(id, [...baseArgs, ...args, ''], onLine: onLine);
    if (!r.ok && !r.canceled) _logFailure('saved info', r.err);
    return r;
  }

  Future<YtInfo> _fetchInfo(String url) async {
    _infoCanceled.remove(url);
    final id = 'info-${DateTime.now().microsecondsSinceEpoch}';
    _infoRunIds[url] = id;
    try {
      await whenReady;
      await _waitForUpdate();
      if (_infoCanceled.contains(url)) throw const YtDlpCanceled();
      return await _fetchInfoRun(url, id);
    } finally {
      _infoRunIds.remove(url);
      _infoCanceled.remove(url);
    }
  }

  Future<YtInfo> _fetchInfoRun(String url, String id) async {
    final sw = Stopwatch()..start();
    final r = await runWithFallback(
      id,
      const ['--dump-single-json', '--skip-download'],
      url,
      // Work the app never uses: HLS manifests, auto-translated subtitles.
      youtubeArgs: 'skip=hls,translated_subs',
      attemptLimit: infoAttemptLimit,
      stopped: () => _infoCanceled.contains(url),
      accept: hasAdaptiveVideo,
    );
    if (_infoCanceled.contains(url)) throw const YtDlpCanceled();
    if (!r.ok) throw YtDlpException(r.err);
    final info = YtInfo.fromJson(jsonDecode(r.out) as Map<String, dynamic>);
    debugPrint('[yt-dlp] info in ${sw.elapsedMilliseconds} ms');
    _infoCache[url] = (at: DateTime.now(), info: info, json: r.out);
    if (_infoCache.length > 50) _infoCache.remove(_infoCache.keys.first);
    return info;
  }

  /// A lookup is only good if it has separate video streams (what HD
  /// downloads are made of). A client that only gets the old combined
  /// 360p stream would silently cap the quality list, so the next one is
  /// tried instead.
  @visibleForTesting
  static bool hasAdaptiveVideo(YtDlpResult r) {
    try {
      final info = jsonDecode(r.out) as Map<String, dynamic>;
      final formats = (info['formats'] as List?) ?? const [];
      return formats.any((f) {
        final m = f as Map<String, dynamic>;
        final v = m['vcodec'] as String?;
        return v != null && v != 'none' && m['acodec'] == 'none';
      });
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------- client fallback

  /// YouTube "player clients" yt-dlp can impersonate, tried in this order;
  /// when one fails (YouTube is uneven per video, network and week) the
  /// next is tried.
  ///  - `visionos`: whole-file HD links with no JS challenge and no PO
  ///    token, so yt-dlp skips downloading YouTube's player script and
  ///    solving it in QuickJS — the ~20 s of a default lookup on a phone.
  ///    Not available for "made for kids" videos.
  ///  - `null` = yt-dlp's own default choice (tv_samsung + visionos + web;
  ///    solves the JS challenge in QuickJS: slow but thorough).
  ///  - `tv`: another client yt-dlp knows without PO tokens (JS challenge).
  ///  - `mweb+pot` = mobile web with PO tokens from our BotGuard WebView.
  /// Dropped (Nov 2026): android_vr (all formats 403 since Aug 2026) and
  /// web_safari (only adds HLS formats, which the app skips).
  static const clientFallbacks = <String?>['visionos', null, 'tv', 'mweb+pot'];

  /// Clients that are a fast first try: any failure moves on to the next.
  static const _fastFirst = {'visionos'};

  /// Extractor args for [client] (+ [extra] YouTube args, merged into the
  /// same `--extractor-args` so neither overrides the other); null when the
  /// client can't be used right now.
  Future<List<String>?> _clientArgs(String? client, String url, {String? extra}) async {
    final tail = extra == null ? '' : ';$extra';
    if (client == null) return extra == null ? const [] : ['--extractor-args', 'youtube:$extra'];
    if (client != 'mweb+pot') return ['--extractor-args', 'youtube:player_client=$client$tail'];
    final id = LinkParser.youtubeVideoId(url);
    if (id == null) return null;
    final t = await PoTokenService.instance.tokensFor(id);
    if (t == null) return null;
    return [
      '--extractor-args',
      'youtube:player_client=mweb;'
          'po_token=mweb.gvs+${t.gvs},mweb.player+${t.player};'
          'visitor_data=${t.visitorData};'
          'player_skip=webpage,configs$tail',
    ];
  }


  /// Errors where another client may succeed (vs. private/removed videos).
  static bool isRetryable(String stderr) {
    final e = stderr.toLowerCase();
    // Age-restricted: only a signed-in adult account gets these (yt-dlp
    // already tried its embedded-player workaround); other clients can't.
    if (isAgeRestricted(e)) return false;
    const signs = [
      '403', 'forbidden', 'http error 4', 'requested format is not available',
      'not a bot', 'sign in to confirm', 'precondition', 'n challenge', 'nsig',
      'signature', 'unable to extract', 'only images are available',
      'no video formats', 'po token', 'unable to download video data',
      // aria2c: 22 = unexpected HTTP response (e.g. 403), 24 = HTTP
      // authorization failed.
      'aria2c exited with code 22', 'aria2c exited with code 24',
    ];
    return signs.any(e.contains);
  }

  /// YouTube's "Sign in to confirm your age" and similar.
  static bool isAgeRestricted(String stderr) {
    final e = stderr.toLowerCase();
    return e.contains('confirm your age') || e.contains('age-restricted') || e.contains('inappropriate for some users');
  }

  /// How long the "looking at the video" phase of a download (before the
  /// download itself starts) may go without a new output line before the
  /// run counts as stuck. Solving YouTube's JS challenge prints nothing for
  /// a while, but not this long.
  static const stallTimeout = Duration(seconds: 40);

  /// Format lookups print nothing until the end (`--dump-single-json` is
  /// quiet), so each attempt gets a plain time limit instead.
  static const infoAttemptLimit = Duration(seconds: 45);

  /// Runs yt-dlp with [args] for [url], retrying with other player clients
  /// when YouTube refuses or the run gets stuck. Stops at once if the run
  /// was canceled or [stopped] says so (user paused).
  Future<YtDlpResult> runWithFallback(
    String id,
    List<String> args,
    String url, {
    void Function(String line)? onLine,
    bool Function()? stopped,
    String? youtubeArgs,
    Duration? attemptLimit,
    bool Function(YtDlpResult result)? accept,
    Set<String?> skip = const {},
  }) async {
    await _waitForUpdate();
    // Always the same order: a client refused for one video (e.g. made for
    // kids) shouldn't make every later lookup slow.
    final order = [for (var i = 0; i < clientFallbacks.length; i++) i];
    var result = const YtDlpResult(exitCode: -1, out: '', err: 'No YouTube client available');
    for (var n = 0; n < order.length; n++) {
      final client = clientFallbacks[order[n]];
      if (skip.contains(client)) continue;
      final clientArgs = await _clientArgs(client, url, extra: youtubeArgs);
      if (clientArgs == null) {
        debugPrint('[yt-dlp] skipping player_client=$client (not available now)');
        continue;
      }
      if (stopped?.call() ?? false) return result;
      if (n > 0) debugPrint('[yt-dlp] retrying with player_client=${client ?? 'default'}');
      final sw = Stopwatch()..start();
      final run = await _runWatched(
        id,
        [...baseArgs, ...clientArgs, ...args, url],
        onLine: onLine,
        limit: attemptLimit,
      );
      result = run.result;
      if (result.ok && accept != null && !accept(result)) {
        debugPrint('[yt-dlp] player_client=${client ?? 'default'} gave no HD formats; trying the next');
        result = YtDlpResult(exitCode: -1, out: '', err: 'ERROR: Requested format is not available');
        continue;
      }
      if (result.ok) {
        debugPrint('[yt-dlp] ok with player_client=${client ?? 'default'} in ${sw.elapsedMilliseconds} ms');
        return result;
      }
      if (run.stalled != null) {
        debugPrint('[yt-dlp] stuck (player_client=${client ?? 'default'}, yt-dlp ${version.value}) '
            'after ${sw.elapsed.inSeconds} s; last output: ${run.stalled}');
        result = YtDlpResult(exitCode: -1, out: '', err: 'ERROR: YouTube took too long to respond');
        if (stopped?.call() ?? false) return result;
        continue;
      }
      if (result.canceled || (stopped?.call() ?? false)) return result;
      _logFailure(client, result.err);
      // The file can't be written: no other client can help.
      if (localFileProblem(result.err) != null) return result;
      // Age-restricted (yt-dlp's embedded-player workaround already tried):
      // only the signed-in account can get it; other clients can't.
      if (isAgeRestricted(result.err)) {
        return _withAccount(id, args, url,
            failed: result, onLine: onLine, youtubeArgs: youtubeArgs, attemptLimit: attemptLimit, accept: accept);
      }
      if (!_fastFirst.contains(client) && !isRetryable(result.err)) return result;
    }
    return result;
  }

  /// Age-restricted [url]: one more run with the user's YouTube sign-in
  /// (yt-dlp then picks its own clients for accounts). [failed] is returned
  /// when nobody is signed in.
  Future<YtDlpResult> _withAccount(
    String id,
    List<String> args,
    String url, {
    required YtDlpResult failed,
    void Function(String line)? onLine,
    String? youtubeArgs,
    Duration? attemptLimit,
    bool Function(YtDlpResult result)? accept,
  }) async {
    final account = YoutubeAccountService.to;
    if (!account.signedIn.value) return failed;
    debugPrint('[yt-dlp] age-restricted; trying with the signed-in YouTube account');
    final sw = Stopwatch()..start();
    final run = await _runWatched(
      id,
      [
        ...baseArgs,
        ...account.ytDlpArgs,
        if (youtubeArgs != null) ...['--extractor-args', 'youtube:$youtubeArgs'],
        ...args,
        url,
      ],
      onLine: onLine,
      // Account lookups solve YouTube's JS challenge (QuickJS): slower.
      limit: attemptLimit == null ? null : attemptLimit * 2,
    );
    final r = run.result;
    if (r.ok && (accept?.call(r) ?? true)) {
      debugPrint('[yt-dlp] ok with the YouTube account in ${sw.elapsedMilliseconds} ms');
      return r;
    }
    if (r.canceled) return r;
    _logFailure('account', r.err);
    if (isSessionExpired(r.err)) await account.markExpired();
    return r.ok ? const YtDlpResult(exitCode: -1, out: '', err: 'ERROR: Requested format is not available') : r;
  }

  /// yt-dlp: "The provided YouTube account cookies are no longer valid".
  static bool isSessionExpired(String stderr) {
    final e = stderr.toLowerCase();
    return e.contains('cookies are no longer valid') || e.contains('account cookies are no longer');
  }

  /// One yt-dlp run with a watchdog. With [limit], the whole run is
  /// canceled after that long. Without it, the extraction phase is watched:
  /// no output line for [stallTimeout] before the download itself starts
  /// cancels the run. `stalled` is then the last line seen (where it got
  /// stuck).
  Future<({YtDlpResult result, String? stalled})> _runWatched(
    String id,
    List<String> args, {
    void Function(String line)? onLine,
    Duration? limit,
  }) async {
    var last = '(no output)';
    final started = DateTime.now();
    var lastAt = started;
    var extracting = true;
    String? stalled;
    final watchdog = Timer.periodic(const Duration(seconds: 5), (t) {
      final now = DateTime.now();
      final stuck = limit != null
          ? now.difference(started) > limit
          : extracting && now.difference(lastAt) > stallTimeout;
      if (limit == null && !extracting) return t.cancel();
      if (stuck) {
        stalled = limit != null ? 'no answer within ${limit.inSeconds} s' : last;
        t.cancel();
        YtDlpBridge.cancel(id);
      }
    });
    try {
      final result = await YtDlpBridge.run(id, args, onLine: (line) {
        lastAt = DateTime.now();
        final l = line.trim();
        if (l.isNotEmpty && l.length < 300) last = l;
        // Extractor / challenge-solver lines look like "[youtube] …",
        // "[jsc:quickjs] …", "[info] …". Anything else (download progress,
        // merging, converting) means extraction is over: long silent steps
        // like converting to MP3 must not trip the watchdog.
        if (extracting && l.isNotEmpty && !_isExtractorLine(l)) extracting = false;
        onLine?.call(line);
      });
      return (result: result, stalled: result.canceled ? stalled : null);
    } finally {
      watchdog.cancel();
    }
  }

  static bool _isExtractorLine(String l) =>
      l.startsWith('[youtube') ||
      l.startsWith('[jsc') ||
      l.startsWith('[info]') ||
      l.startsWith('[debug]') ||
      l.startsWith('WARNING') ||
      l.startsWith('{'); // --dump-single-json output

  void _logFailure(String? client, String stderr) {
    final lines = stderr.split('\n').where((l) => l.trim().isNotEmpty).toList();
    final tail = lines.length > 12 ? lines.sublist(lines.length - 12) : lines;
    debugPrint('[yt-dlp] failed (player_client=${client ?? 'default'}, '
        'yt-dlp ${version.value}):\n${tail.join('\n')}');
  }
}
