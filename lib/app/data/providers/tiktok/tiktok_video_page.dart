import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'tiktok_feed.dart';

/// What TikTok's video page answered: `comments`, `replies`, `like` (the
/// video's like) or `commentLike`, with the request's [url] (which video
/// or comment, like or unlike) and the answer [text].
class TiktokPageEvent {
  const TiktokPageEvent(this.kind, this.text, this.url);

  final String kind;
  final String text;
  final String url;

  /// A query parameter of the request ("aweme_id", "type", "cid", …).
  String? param(String name) => Uri.tryParse(url)?.queryParameters[name];

  /// TikTok accepted it (`status_code` 0).
  bool get ok {
    try {
      final j = jsonDecode(text);
      return j is Map && (j['status_code'] == 0 || j['status_code'] == '0');
    } catch (_) {
      return false;
    }
  }
}

/// One TikTok video's own page, for what needs TikTok itself: its comments
/// and replies, and liking (the page's own buttons are pressed, so TikTok
/// signs the requests; Toomu never builds them).
abstract class TiktokVideoPage {
  ValueListenable<Widget?> get page;
  Stream<TiktokPageEvent> get events;

  /// Shows [url] (nothing if it already does).
  Future<void> open(String url);

  /// Runs one of [WebTiktokVideoPage.pageJs]'s commands once the page is there.
  Future<void> run(String command);

  Future<void> close();
}

/// [TiktokVideoPage] as a WebView kept under the feed (drawn, never seen),
/// like the feed pages. Comment answers are empty for visitors (checked in
/// Chrome): comments and likes need the account.
class WebTiktokVideoPage implements TiktokVideoPage {
  final _events = StreamController<TiktokPageEvent>.broadcast();
  final _page = ValueNotifier<Widget?>(null);
  InAppWebViewController? _controller;
  String? _url;
  Completer<void> _loaded = Completer<void>();

  /// The page has this long to load before a command is given up.
  static Duration loadTimeout = const Duration(seconds: 40);

  @override
  ValueListenable<Widget?> get page => _page;

  @override
  Stream<TiktokPageEvent> get events => _events.stream;

  @override
  Future<void> open(String url) async {
    if (_url == url && _page.value != null) return;
    _url = url;
    _loaded = Completer<void>();
    final c = _controller;
    debugPrint('[TikTok] video page: $url');
    if (c != null) {
      await c.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
      return;
    }
    _page.value = Builder(key: UniqueKey(), builder: (_) => _webView(url));
  }

  Widget _webView(String url) => InAppWebView(
    initialUrlRequest: URLRequest(
      url: WebUri(url),
      headers: const {'Accept-Language': 'en-US,en;q=0.9'},
    ),
    initialSettings: WebTiktokFeedSource.settings(),
    initialUserScripts: UnmodifiableListView<UserScript>([
      UserScript(
        source: pageJs,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      ),
    ]),
    onWebViewCreated: (c) {
      _controller = c;
      c.addJavaScriptHandler(
        handlerName: 'toomuTiktokPage',
        callback: (List<dynamic> args) {
          if (args.length >= 3 && !_events.isClosed) {
            final e = TiktokPageEvent('${args[0]}', '${args[1]}', '${args[2]}');
            debugPrint(
              '[TikTok] video page: ${e.kind} ${e.ok ? 'ok' : 'answer ${e.text.length} chars'}',
            );
            _events.add(e);
          } else if (args.length == 1) {
            debugPrint('[TikTok] video page: ${args[0]}');
          }
          return null;
        },
      );
    },
    onLoadStop: (_, _) {
      if (!_loaded.isCompleted) _loaded.complete();
    },
  );

  @override
  Future<void> run(String command) async {
    try {
      await _loaded.future.timeout(loadTimeout);
    } on TimeoutException {
      debugPrint('[TikTok] video page: not loaded, running anyway');
    }
    final c = _controller;
    if (c == null) return;
    try {
      await c.evaluateJavascript(source: command);
    } catch (e) {
      debugPrint('[TikTok] video page: $command failed: $e');
    }
  }

  @override
  Future<void> close() async {
    _controller = null;
    _url = null;
    _page.value = null;
  }

  static String call(String fn, [String? arg]) =>
      'window.$fn && window.$fn(${arg == null ? '' : jsonEncode(arg)})';

  /// Runs in the video page from its first line: copies TikTok's comment,
  /// reply and like answers out, keeps the page silent, and has commands
  /// that press the page's own buttons. The like and comment buttons are
  /// TikTok's `data-e2e="like-icon"` / `"comment-icon"` (checked in Chrome);
  /// a comment is found by its text, and its like and "View replies" inside
  /// it (TikTok's comment markup could only be seen signed in).
  @visibleForTesting
  static const pageJs = r'''
(() => {
  if (window.__toomuPage) return;
  window.__toomuPage = true;
  const send = (...args) => {
    try { window.flutter_inappwebview.callHandler('toomuTiktokPage', ...args); } catch (e) {}
  };
  const kinds = [
    [/\/api\/comment\/list\/reply/, 'replies'],
    [/\/api\/comment\/list/, 'comments'],
    [/\/api\/comment\/digg/, 'commentLike'],
    [/\/api\/commit\/item\/digg/, 'like'],
  ];
  const kindOf = (u) => { for (const [re, k] of kinds) if (re.test(u || '')) return k; return null; };
  const abs = (u) => { try { return new URL(u, location.href).href; } catch (e) { return String(u); } };

  const realFetch = window.fetch;
  window.fetch = function (input, init) {
    const p = realFetch.apply(this, arguments);
    try {
      const url = abs(typeof input === 'string' ? input : (input && input.url) || String(input));
      const kind = kindOf(url);
      if (kind) p.then((r) => r.clone().text()).then((t) => send(kind, t, url)).catch(() => {});
    } catch (e) {}
    return p;
  };
  const open = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function (m, u) {
    this.__toomuUrl = abs(u);
    this.__toomuKind = kindOf(this.__toomuUrl);
    return open.apply(this, arguments);
  };
  const sendXhr = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.send = function () {
    if (this.__toomuKind) {
      this.addEventListener('load', () => {
        try {
          send(this.__toomuKind, this.responseType === 'json' ? JSON.stringify(this.response) : this.responseText, this.__toomuUrl);
        } catch (e) {}
      });
    }
    return sendXhr.apply(this, arguments);
  };

  const quiet = () => document.querySelectorAll('video,audio').forEach((v) => { v.muted = true; if (!v.paused) v.pause(); });
  document.addEventListener('play', quiet, true);
  setInterval(quiet, 1500);

  const until = (find, ms) => new Promise((done) => {
    const t0 = Date.now();
    const look = () => {
      let el = null;
      try { el = find(); } catch (e) {}
      if (el) return done(el);
      if (Date.now() - t0 > ms) return done(null);
      setTimeout(look, 300);
    };
    look();
  });
  const press = (el) => (el.closest('button,[role="button"]') || el).click();

  // The comment whose text is exactly [text] (its innermost element).
  const commentText = (text) => {
    const want = (text || '').trim();
    for (const el of document.querySelectorAll('p,span,div')) {
      if (el.childElementCount === 0 && el.textContent.trim() === want) return el;
    }
    return null;
  };
  // Going up from [el], the first box that holds [find]'s element.
  const near = (el, find) => {
    let box = el;
    for (let i = 0; i < 8 && box; i++) {
      box = box.parentElement;
      const hit = box && find(box);
      if (hit) return hit;
    }
    return null;
  };
  const likeIn = (box) => box.querySelector('[data-e2e*="comment-like"], [data-e2e*="like-icon"], [aria-label*="ike"]');
  const repliesIn = (box) => [...box.querySelectorAll('p,span,div,button')].find(
    (e) => e.childElementCount <= 2 && /^(view\s+\d+\s+repl|view\s+more|\d+\s+repl)/i.test(e.textContent.trim()));

  window.__toomuOpenComments = async () => {
    const el = await until(() => document.querySelector('[data-e2e="comment-icon"]'), 30000);
    if (!el) return send('no comment button');
    press(el);
  };
  window.__toomuLike = async () => {
    const el = await until(() => document.querySelector('[data-e2e="like-icon"]'), 30000);
    if (!el) return send('no like button');
    press(el);
  };
  window.__toomuMoreComments = async (lastText) => {
    const el = commentText(lastText);
    if (!el) return send('more comments: last comment not found');
    let box = el.parentElement;
    while (box && !(box.scrollHeight > box.clientHeight + 20 && /auto|scroll/.test(getComputedStyle(box).overflowY))) box = box.parentElement;
    (box || document.scrollingElement).scrollTop = (box || document.scrollingElement).scrollHeight;
    el.scrollIntoView({ block: 'end' });
  };
  window.__toomuReplies = async (text) => {
    const el = await until(() => commentText(text), 10000);
    const more = el && near(el, repliesIn);
    if (!more) return send('replies: button not found');
    press(more);
  };
  window.__toomuLikeComment = async (text) => {
    const el = await until(() => commentText(text), 10000);
    const like = el && near(el, likeIn);
    if (!like) return send('comment like: button not found');
    press(like);
  };
})();
''';
}
