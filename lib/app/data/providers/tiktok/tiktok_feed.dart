import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../services/tiktok_account_service.dart';
import '../../../services/tiktok_service.dart';
import '../../models/tiktok_item.dart';

/// Where the TikTok tab's videos come from.
abstract class TiktokFeedSource {
  /// New videos as TikTok hands them out (ads already left out).
  Stream<List<TiktokItem>> get batches;

  /// Starts loading the feed (nothing if it already runs).
  Future<void> start();

  /// Asks for the next batch (starts the feed again if it was closed).
  Future<void> more();

  /// Stops the feed (frees the browser engine behind it).
  Future<void> close();

  /// The page the feed comes from, while it runs: the TikTok tab keeps it
  /// in its widget tree, under the feed, so it is drawn (never seen).
  ValueListenable<Widget?> get page;

  /// Off while the tab isn't on screen: the page stops drawing; with
  /// [background] (the app hidden) its scripts stop too.
  void setActive(bool on, {bool background = false});
}

/// TikTok's data → videos.
abstract class TiktokFeed {
  /// The videos in one message from [WebTiktokFeedSource]'s script:
  /// `page` = the For You page's embedded data (its first videos),
  /// `feed` = an answer of TikTok's feed API. Ads, photo slideshows and
  /// videos without a file are left out; unreadable data gives none.
  static List<TiktokItem> parse(String kind, String text) {
    try {
      final data = jsonDecode(text);
      if (data is! Map) return const [];
      Object? list = data['itemList'];
      if (kind == 'page') {
        // For You: "webapp.foryou.video"; any other page's video list too.
        list = null;
        final scope = data['__DEFAULT_SCOPE__'];
        if (scope is Map) {
          for (final part in scope.values) {
            if (part is Map && part['itemList'] is List) {
              list = part['itemList'];
              break;
            }
          }
        }
      }
      if (list is! List) return const [];
      return [
        for (final j in list)
          if (j is Map<String, dynamic>) TiktokItem.fromJson(j),
      ].whereType<TiktokItem>().where((i) => i.playUrl.isNotEmpty).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Who is signed in, from a TikTok page's embedded data
  /// (`webapp.app-context` has a `user` only for a signed-in visit).
  static TiktokUser? userFrom(String pageText) {
    try {
      final data = jsonDecode(pageText);
      final scope = data is Map ? data['__DEFAULT_SCOPE__'] : null;
      final context = scope is Map ? scope['webapp.app-context'] : null;
      final user = context is Map ? context['user'] : null;
      if (user is! Map) return null;
      final id = user['uniqueId'];
      if (id is! String || id.isEmpty) return null;
      final avatar =
          user['avatarUri'] ?? user['avatarThumb'] ?? user['avatarMedium'];
      return TiktokUser(
        id: id,
        name: ((user['nickName'] ?? user['nickname']) as String?) ?? '',
        avatar: avatar is List && avatar.isNotEmpty
            ? '${avatar.first}'
            : avatar is String
            ? avatar
            : null,
      );
    } catch (_) {
      return null;
    }
  }
}

/// TikTok's own For You (or Following) page in a WebView: TikTok's scripts sign the feed
/// requests (as for any visitor, no account), and [feedJs] copies their
/// answers out. Videos then play in Toomu's player, so none of TikTok's
/// ads, pop-ups or sign-in walls are ever shown, and its page stays silent.
///
/// The page is a real WebView in the TikTok tab (under the feed), not a
/// headless one: on Android a headless WebView is invisible, an invisible
/// WebView draws no frames, and without frames TikTok's page never noticed
/// the scrolling, so only its first two videos ever came.
class WebTiktokFeedSource implements TiktokFeedSource {
  WebTiktokFeedSource({
    this.url = forYouUrl,
    this.api = forYouApi,
    this.name = 'For You',
    this.onUser,
  });

  /// The For You feed (checked in Chrome).
  WebTiktokFeedSource.forYou({void Function(TiktokUser? user)? onUser})
    : this(onUser: onUser);

  /// The Following feed: videos of the accounts the signed-in user follows.
  /// A visitor's Following page has no videos (only suggested accounts).
  WebTiktokFeedSource.following({void Function(TiktokUser? user)? onUser})
    : this(
        url: followingUrl,
        api: followingApi,
        name: 'Following',
        onUser: onUser,
      );

  static const forYouUrl = 'https://www.tiktok.com/foryou';
  static const followingUrl = 'https://www.tiktok.com/following';

  /// The feed requests whose answers are copied (a JavaScript regex).
  static const forYouApi = r'\/api\/(recommend|preload)\/item_list';
  static const followingApi = r'\/api\/[a-z_\/]*follow[a-z_\/]*item_list';

  final String url;
  final String api;
  final String name;

  /// Told who is signed in each time the page loads.
  final void Function(TiktokUser? user)? onUser;

  final _batches = StreamController<List<TiktokItem>>.broadcast();
  final _page = ValueNotifier<Widget?>(null);
  InAppWebViewController? _controller;
  bool _active = true;
  bool _timersPaused = false;

  @override
  Stream<List<TiktokItem>> get batches => _batches.stream;

  @override
  ValueListenable<Widget?> get page => _page;

  @override
  Future<void> start() async {
    if (_page.value != null) return;
    debugPrint('[TikTok] feed: opening the $name page');
    // Made when the tab builds it (the WebView needs the platform side).
    _page.value = Builder(key: UniqueKey(), builder: (_) => _webView());
  }

  Widget _webView() {
    return InAppWebView(
      initialUrlRequest: URLRequest(
        url: WebUri(url),
        headers: const {'Accept-Language': 'en-US,en;q=0.9'},
      ),
      initialSettings: settings(),
      initialUserScripts: UnmodifiableListView<UserScript>([
        UserScript(
          source: scriptFor(api),
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
      ]),
      onWebViewCreated: (c) {
        _controller = c;
        if (!_active) unawaited(_apply(c, false, background: _timersPaused));
        c.addJavaScriptHandler(
          handlerName: 'toomuTiktok',
          callback: (List<dynamic> args) {
            if (args.length >= 2) _take('${args[0]}', '${args[1]}');
            return null;
          },
        );
      },
      onReceivedError: (_, request, error) {
        if (request.isForMainFrame ?? false) {
          debugPrint('[TikTok] feed page failed: ${error.description}');
        }
      },
    );
  }

  /// Also used by the video page (comments, likes): same identity.
  static InAppWebViewSettings settings() => InAppWebViewSettings(
    javaScriptEnabled: true,
    userAgent: TiktokService.agent,
    mediaPlaybackRequiresUserGesture: true,
    preferredContentMode: UserPreferredContentMode.DESKTOP,
    // Its pictures aren't shown to anyone (Android; checked: the feed
    // still loads). Less data next to the video playing.
    blockNetworkImage: true,
    supportZoom: false,
    disableContextMenu: true,
    // A texture, not hybrid composition: with hybrid composition every
    // frame of the feed above it was composed with the page through extra
    // layers, and swiping stuttered. It still draws (so it keeps loading).
    useHybridComposition: false,
  );

  void _take(String kind, String text) {
    if (kind == 'page') onUser?.call(TiktokFeed.userFrom(text));
    final items = TiktokFeed.parse(kind, text);
    debugPrint('[TikTok] $name: $kind → ${items.length} videos');
    if (items.isNotEmpty && !_batches.isClosed) _batches.add(items);
  }

  @override
  Future<void> more() async {
    final c = _controller;
    if (c == null) {
      // Closed: open again (its first batch comes on its own).
      if (_page.value == null) await start();
      return;
    }
    try {
      await c.evaluateJavascript(
        source: 'window.__toomuMore && window.__toomuMore()',
      );
    } catch (e) {
      debugPrint('[TikTok] feed: more failed: $e');
    }
  }

  @override
  void setActive(bool on, {bool background = false}) {
    _active = on;
    final c = _controller;
    if (c != null) unawaited(_apply(c, on, background: background));
  }

  Future<void> _apply(
    InAppWebViewController c,
    bool on, {
    required bool background,
  }) async {
    if (!Platform.isAndroid) return; // Windows: nothing to pause per page
    try {
      if (on) {
        if (_timersPaused) await c.resumeTimers();
        _timersPaused = false;
        await c.resume();
      } else {
        await c.pause(); // drawing, media
        // Scripts too, only with the whole app hidden: pauseTimers stops
        // every WebView in the app (the browser does the same then).
        if (background) {
          await c.pauseTimers();
          _timersPaused = true;
        }
      }
      debugPrint(
        '[TikTok] feed page ${on
            ? 'running'
            : background
            ? 'paused (app in background)'
            : 'paused'}',
      );
    } catch (e) {
      debugPrint('[TikTok] feed page pause/resume: $e');
    }
  }

  @override
  Future<void> close() async {
    if (_page.value != null) debugPrint('[TikTok] feed: closed');
    _controller = null;
    _page.value = null; // the WebView goes with its widget
  }

  /// Runs in TikTok's page from its first line: copies the feed out
  /// (`page` once, `feed` per batch), keeps the page's own players silent,
  /// and `__toomuMore()` scrolls TikTok's feed to its end, where it loads
  /// the next batch. Checked against tiktok.com in Chrome (as a visitor:
  /// ~12 videos per batch, a few ads among them).
  /// [feedJs] watching the feed requests that match [api].
  @visibleForTesting
  static String scriptFor(String api) => feedJs.replaceFirst('__API__', api);

  static const feedJs = r'''
(() => {
  if (window.__toomuFeed) return;
  window.__toomuFeed = true;
  const send = (kind, text) => {
    try { window.flutter_inappwebview.callHandler('toomuTiktok', kind, text); } catch (e) {}
  };
  const wanted = (u) => /__API__/.test(u || '');

  const realFetch = window.fetch;
  window.fetch = function (input, init) {
    const p = realFetch.apply(this, arguments);
    try {
      const url = typeof input === 'string' ? input : (input && input.url) || String(input);
      if (wanted(url)) p.then((r) => r.clone().text()).then((t) => send('feed', t)).catch(() => {});
    } catch (e) {}
    return p;
  };
  const open = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function (m, u) {
    this.__toomu = wanted(String(u));
    return open.apply(this, arguments);
  };
  const sendXhr = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.send = function () {
    if (this.__toomu) {
      this.addEventListener('load', () => {
        try {
          send('feed', this.responseType === 'json' ? JSON.stringify(this.response) : this.responseText);
        } catch (e) {}
      });
    }
    return sendXhr.apply(this, arguments);
  };

  const quiet = () => document.querySelectorAll('video,audio').forEach((v) => {
    v.muted = true;
    if (!v.paused) v.pause();
  });
  document.addEventListener('play', quiet, true);
  setInterval(quiet, 1500);

  const first = () => {
    const s = document.getElementById('__UNIVERSAL_DATA_FOR_REHYDRATION__');
    if (s) send('page', s.textContent);
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', first);
  else first();

  window.__toomuMore = () => {
    let box = document.scrollingElement || document.documentElement;
    let best = box.scrollHeight - box.clientHeight;
    document.querySelectorAll('div,main,section').forEach((el) => {
      const extra = el.scrollHeight - el.clientHeight;
      if (extra > best + 50) {
        const o = getComputedStyle(el).overflowY;
        if (o === 'auto' || o === 'scroll') { box = el; best = extra; }
      }
    });
    box.scrollTop = box.scrollHeight;
    box.dispatchEvent(new Event('scroll'));
    document.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowDown', code: 'ArrowDown', keyCode: 40, bubbles: true }));
    return true;
  };
})();
''';
}
