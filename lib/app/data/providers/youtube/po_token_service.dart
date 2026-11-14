import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get_storage/get_storage.dart';

/// Generates YouTube PO ("proof of origin") tokens for yt-dlp, the way
/// NewPipe does: YouTube's own BotGuard script runs in a hidden WebView
/// (youtube.com origin), its answer is exchanged for an integrity token, and
/// that token mints per-identifier PO tokens.
///
/// yt-dlp then gets them via its documented extractor args:
/// `youtube:player_client=mweb;po_token=mweb.gvs+…,mweb.player+…;visitor_data=…`
/// * GVS token: minted for the visitor id; lets the video servers serve the
///   whole file instead of answering 403.
/// * Player token: minted for the video id.
class PoTokenService {
  PoTokenService._();

  static final PoTokenService instance = PoTokenService._();

  // Public constants of YouTube's web player (also used by NewPipe/bgutils).
  static const _requestKey = 'O43z0dpjhgX20SCx4KAo';
  static const _apiKey = 'AIzaSyDyT5W0Jh49F30Pqqtyfdf7pDLFKLJoAnw';
  static const _timeout = Duration(seconds: 45);
  static const _kVisitorData = 'yt_visitor_data';

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
    responseType: ResponseType.plain,
  ));

  HeadlessInAppWebView? _webView;
  InAppWebViewController? _controller;
  Future<void>? _session;
  DateTime? _sessionExpires;
  String? _visitorData;
  final Map<String, String> _minted = {};
  Future<void> _queue = Future<void>.value();

  /// The WebView (a whole browser engine running YouTube's BotGuard) is
  /// closed after this long unused, so it doesn't keep the CPU busy.
  static const _idleClose = Duration(minutes: 2);
  Timer? _idleTimer;

  /// Tokens for [videoId], or null if generation failed.
  Future<({String visitorData, String gvs, String player})?> tokensFor(String videoId) async {
    try {
      final visitor = await _visitorId();
      final gvs = await _mint(visitor);
      final player = await _mint(videoId);
      return (visitorData: visitor, gvs: gvs, player: player);
    } catch (e) {
      debugPrint('[PoToken] failed: $e');
      return null;
    }
  }

  /// Persisted so YouTube sees one consistent visitor.
  Future<String> _visitorId() async {
    if (_visitorData != null) return _visitorData!;
    final box = GetStorage();
    final saved = box.read<String>(_kVisitorData);
    if (saved != null && saved.isNotEmpty) return _visitorData = saved;
    var body = (await _dio.get<String>('https://www.youtube.com/sw.js_data')).data ?? '';
    if (body.startsWith(")]}'")) body = body.substring(4);
    final data = json.decode(body) as List<dynamic>;
    final value = data[0][2][0][0][13] as String;
    await box.write(_kVisitorData, value);
    return _visitorData = value;
  }

  Future<String> _mint(String identifier) {
    final cached = _minted[identifier];
    if (cached != null && _sessionValid) return Future.value(cached);
    _idleTimer?.cancel();
    final run = _queue.then((_) async {
      await _ensureSession();
      final result = await _controller!.callAsyncJavaScript(
        functionBody: 'return await mintToken(identifier);',
        arguments: {'identifier': identifier},
      ).timeout(_timeout);
      if (result == null || result.error != null || result.value is! String) {
        throw StateError('mint failed: ${result?.error}');
      }
      return _minted[identifier] = result.value as String;
    });
    _queue = run.then((_) {}, onError: (_) {});
    _queue.then((_) {
      _idleTimer?.cancel();
      _idleTimer = Timer(_idleClose, () => _queue = _queue.then((_) => _close()));
    });
    return run;
  }

  /// Frees the WebView; the next token request starts a new session.
  Future<void> _close() async {
    if (_webView == null) return;
    try {
      await _webView!.dispose();
    } catch (_) {}
    _webView = null;
    _controller = null;
    _session = null;
    _sessionExpires = null;
    _minted.clear();
    debugPrint('[PoToken] WebView closed (idle)');
  }

  bool get _sessionValid =>
      _session != null && _sessionExpires != null && DateTime.now().isBefore(_sessionExpires!);

  Future<void> _ensureSession() {
    if (!_sessionValid) {
      _minted.clear();
      _session = _createSession().catchError((Object e) {
        _session = null;
        throw e;
      });
    }
    return _session!;
  }

  Future<void> _createSession() async {
    await _ensureWebView();

    // 1. BotGuard challenge.
    final data = _parseChallenge(await _jnn('Create', [_requestKey]));
    var interpreter = data.interpreterJs;
    if (interpreter == null && data.interpreterUrl != null) {
      final url = data.interpreterUrl!.startsWith('//') ? 'https:${data.interpreterUrl}' : data.interpreterUrl!;
      interpreter = (await _dio.get<String>(url)).data;
    }
    if (interpreter == null) throw StateError('No BotGuard interpreter');

    // 2. Run BotGuard in the WebView.
    final bg = await _controller!.callAsyncJavaScript(
      functionBody: 'return await runBotGuard(interpreter, program, globalName);',
      arguments: {'interpreter': interpreter, 'program': data.program, 'globalName': data.globalName},
    ).timeout(_timeout);
    if (bg == null || bg.error != null || bg.value is! String) {
      throw StateError('BotGuard failed: ${bg?.error}');
    }

    // 3. Integrity token.
    final it = json.decode(await _jnn('GenerateIT', [_requestKey, bg.value])) as List<dynamic>;
    final integrityToken = it[0] as String;
    final ttl = (it[1] as num?)?.toInt() ?? 3600;

    // 4. Minter.
    final init = await _controller!.callAsyncJavaScript(
      functionBody: 'return await initMinter(token);',
      arguments: {'token': integrityToken},
    ).timeout(_timeout);
    if (init == null || init.error != null) throw StateError('Minter failed: ${init?.error}');

    _sessionExpires = DateTime.now().add(Duration(seconds: (ttl * 0.9).round()));
    debugPrint('[PoToken] session ready (ttl ${ttl}s)');
  }

  Future<String> _jnn(String method, List<Object?> body) async {
    final r = await _dio.post<String>(
      'https://www.youtube.com/api/jnn/v1/$method',
      data: json.encode(body),
      options: Options(headers: {
        'content-type': 'application/json+protobuf',
        'x-goog-api-key': _apiKey,
        'x-user-agent': 'grpc-web-javascript/0.1',
      }),
    );
    return r.data ?? '';
  }

  static ({String? interpreterJs, String? interpreterUrl, String program, String globalName})
      _parseChallenge(String raw) {
    final outer = json.decode(raw) as List<dynamic>;
    List<dynamic> c;
    if (outer.length > 1 && outer[1] is String) {
      // Scrambled form: base64, then every byte shifted by 97.
      final bytes = base64.decode(base64.normalize(outer[1] as String));
      c = json.decode(utf8.decode(bytes.map((b) => (b + 97) & 0xff).toList())) as List<dynamic>;
    } else {
      c = outer[0] as List<dynamic>;
    }
    String? firstString(Object? v) =>
        v is List ? v.whereType<String>().where((s) => s.isNotEmpty).firstOrNull : null;
    return (
      interpreterJs: firstString(c[1]),
      interpreterUrl: firstString(c[2]),
      program: c[4] as String,
      globalName: c[5] as String,
    );
  }

  Future<void> _ensureWebView() async {
    if (_controller != null) return;
    final loaded = Completer<void>();
    _webView = HeadlessInAppWebView(
      initialData: InAppWebViewInitialData(data: _page, baseUrl: WebUri('https://www.youtube.com/')),
      initialSettings: InAppWebViewSettings(javaScriptEnabled: true),
      onWebViewCreated: (c) => _controller = c,
      onLoadStop: (_, _) {
        if (!loaded.isCompleted) loaded.complete();
      },
    );
    await _webView!.run();
    await loaded.future.timeout(_timeout);
  }

  static const _page = r'''<!doctype html><html><head><script>
function b64ToU8(s) {
  s = s.replace(/-/g, '+').replace(/_/g, '/');
  while (s.length % 4) s += '=';
  const bin = atob(s);
  const u8 = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) u8[i] = bin.charCodeAt(i);
  return u8;
}
function u8ToB64Url(u8) {
  let bin = '';
  for (let i = 0; i < u8.length; i++) bin += String.fromCharCode(u8[i]);
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_');
}
async function runBotGuard(interpreter, program, globalName) {
  new Function(interpreter)();
  const vm = globalThis[globalName];
  if (!vm || typeof vm.a !== 'function') throw new Error('BotGuard VM not found');
  let snapshot = null;
  vm.a(program, (asyncSnapshot) => { snapshot = asyncSnapshot; }, true, undefined, () => {}, [[], []]);
  for (let i = 0; i < 200 && !snapshot; i++) await new Promise(r => setTimeout(r, 50));
  if (!snapshot) throw new Error('BotGuard did not start');
  const webPoSignalOutput = [];
  const response = await new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('BotGuard snapshot timeout')), 30000);
    snapshot((r) => { clearTimeout(t); resolve(r); }, [undefined, undefined, webPoSignalOutput, undefined]);
  });
  window.__webPoSignalOutput = webPoSignalOutput;
  return response;
}
async function initMinter(token) {
  const getMinter = (window.__webPoSignalOutput || [])[0];
  if (typeof getMinter !== 'function') throw new Error('PO minter not available');
  window.__mint = await getMinter(b64ToU8(token));
  if (typeof window.__mint !== 'function') throw new Error('PO minter invalid');
  return true;
}
async function mintToken(identifier) {
  const out = await window.__mint(new TextEncoder().encode(identifier));
  if (!(out instanceof Uint8Array)) throw new Error('Unexpected mint result');
  return u8ToB64Url(out);
}
</script></head><body></body></html>''';
}
