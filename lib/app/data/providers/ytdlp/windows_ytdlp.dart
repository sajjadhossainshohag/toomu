import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'ytdlp_bridge.dart';

/// yt-dlp on Windows: the official `yt-dlp.exe`, FFmpeg and Deno (yt-dlp's
/// JS runtime for YouTube's challenges), downloaded from GitHub on first
/// launch into `%APPDATA%\…\tools` and run as processes. The Windows side
/// of [YtDlpBridge]; Android uses youtubedl-android instead.
///
/// Like the Android bridge, updates only use github.com release pages and
/// files (the GitHub API's 60 requests/hour per IP are often used up).
class WindowsYtDlp {
  /// Every part that touches the outside world can be swapped for tests;
  /// the defaults are the real ones.
  WindowsYtDlp({
    Future<String> Function()? toolsDir,
    Uri? github,
    Uri? ffmpegZip,
    Uri? denoZip,
    ToolLauncher? launch,
    Future<void> Function(String zip, String outDir)? unzip,
    Future<void> Function(Process process)? killTree,
    this.minBinaryBytes = 5 << 20,
  }) : _toolsDir = toolsDir ?? _defaultToolsDir,
       _github = github ?? Uri.parse('https://github.com'),
       _ffmpegZip = ffmpegZip ??
           Uri.parse('https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip'),
       _denoZip = denoZip ??
           Uri.parse('https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip'),
       _launch = launch ?? _defaultLaunch,
       _unzip = unzip ?? _tarUnzip,
       _killTree = killTree ?? _taskkill;

  /// The one the app uses (tests swap in one pointed at a fake GitHub).
  static WindowsYtDlp instance = WindowsYtDlp();

  final Future<String> Function() _toolsDir;
  final Uri _github;
  final Uri _ffmpegZip;
  final Uri _denoZip;
  final ToolLauncher _launch;
  final Future<void> Function(String zip, String outDir) _unzip;
  final Future<void> Function(Process process) _killTree;

  /// A smaller download is an error page or cut short, not yt-dlp.exe
  /// (~18 MB).
  final int minBinaryBytes;

  static Future<String> _defaultToolsDir() async => '${(await getApplicationSupportDirectory()).path}\\tools';

  static Future<Process> _defaultLaunch(String exe, List<String> args) =>
      Process.start(exe, args, environment: const {'PYTHONIOENCODING': 'utf-8', 'PYTHONUTF8': '1'});

  /// Windows 10's built-in `tar` reads zip files.
  static Future<void> _tarUnzip(String zip, String outDir) async {
    final r = await Process.run('tar', ['-xf', zip, '-C', outDir]);
    if (r.exitCode != 0) throw ToolInstallException('Unzipping failed: ${r.stderr}');
  }

  /// yt-dlp.exe starts Python, which starts FFmpeg: all of them go.
  static Future<void> _taskkill(Process p) async {
    final r = await Process.run('taskkill', ['/PID', '${p.pid}', '/T', '/F']);
    if (r.exitCode != 0) p.kill();
  }

  static final _sep = Platform.pathSeparator;

  final _progress = StreamController<({String id, String line})>.broadcast();
  final Map<String, Process> _running = {};
  final Set<String> _canceled = {};

  String _dir = '';
  Future<void>? _init;

  /// FFmpeg + Deno; downloads wait for it, lookups don't.
  Future<void>? _extras;
  Future<void>? _updating;

  String get _ytdlp => '$_dir${_sep}yt-dlp.exe';
  String get _ffmpegDir => '$_dir${_sep}ffmpeg';
  String get _deno => '$_dir${_sep}deno.exe';
  File get _state => File('$_dir${_sep}state.json');

  Stream<({String id, String line})> get lines => _progress.stream;

  Future<String?> init() async {
    await _ensure();
    return version();
  }

  /// Sets up once; a failed first install (offline) is tried again on the
  /// next call.
  Future<void> _ensure() => _init ??= _setUp().catchError((Object e) {
    _init = null;
    throw e;
  });

  Future<void> _setUp() async {
    _dir = await _toolsDir();
    await Directory(_dir).create(recursive: true);
    // An update cut short between moving the old one aside and the new one in.
    final backup = File('$_ytdlp.old');
    if (!File(_ytdlp).existsSync() && backup.existsSync()) await backup.rename(_ytdlp);
    if (!File(_ytdlp).existsSync()) {
      final tag = await _latestTag(nightly: false);
      await _installYtDlp(tag, nightly: false);
    }
    _extras = _installExtras();
  }

  /// Completes once the background FFmpeg/Deno install has finished.
  @visibleForTesting
  Future<void> get backgroundWork async => _extras?.catchError((Object _) {});

  bool get _hasFfmpeg => File('$_ffmpegDir${_sep}ffmpeg.exe').existsSync();

  Future<void> _installExtras() async {
    try {
      await _installExtrasOnce();
    } finally {
      // Failed (offline?): the next download tries again.
      if (!_hasFfmpeg || !File(_deno).existsSync()) _extras = null;
    }
  }

  Future<void> _installExtrasOnce() async {
    try {
      if (!_hasFfmpeg) {
        await _installFromZip(_ffmpegZip, {'ffmpeg.exe', 'ffprobe.exe'}, _ffmpegDir);
      }
    } catch (e) {
      debugPrint('[yt-dlp] FFmpeg download failed: $e');
    }
    try {
      if (!File(_deno).existsSync()) await _installFromZip(_denoZip, {'deno.exe'}, _dir);
    } catch (e) {
      debugPrint('[yt-dlp] Deno download failed: $e');
    }
  }

  Map<String, dynamic> _readState() {
    try {
      return jsonDecode(_state.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  void _writeState(Map<String, dynamic> s) => _state.writeAsStringSync(jsonEncode(s));

  Future<String?> version() async {
    await _ensure();
    final saved = _readState()['version'] as String?;
    if (saved != null) return saved;
    final v = await _runVersion();
    if (v != null) _writeState({..._readState(), 'version': v});
    return v;
  }

  Future<String?> _runVersion() async {
    try {
      final p = await _launch(_ytdlp, const ['--version']);
      final out = p.stdout.transform(const Utf8Decoder(allowMalformed: true)).join();
      await p.stderr.drain<void>();
      if (await p.exitCode != 0) return null;
      final lines = (await out).split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);
      return lines.isEmpty ? null : lines.last;
    } catch (_) {
      return null;
    }
  }

  /// No release tag recorded yet: the first install wasn't from an update.
  Future<bool> needsUpdate() async {
    await _ensure();
    return _readState()['tag'] == null;
  }

  Future<String> update(String channel) async {
    await _ensure();
    final previous = _updating;
    if (previous != null) await previous.catchError((Object _) {});
    final nightly = channel == 'nightly';
    final done = Completer<void>();
    _updating = done.future;
    try {
      final tag = await _latestTag(nightly: nightly);
      if (tag == _readState()['tag'] && File(_ytdlp).existsSync()) return 'ALREADY_UP_TO_DATE';
      await _installYtDlp(tag, nightly: nightly);
      return 'DONE';
    } finally {
      done.complete();
      _updating = null;
    }
  }

  /// Downloads yt-dlp.exe [tag] next to the working one, checks that it
  /// starts, then swaps it in (the old one is kept if it doesn't).
  Future<void> _installYtDlp(String tag, {required bool nightly}) async {
    final tmp = File('$_ytdlp.download');
    await _download(_github.resolve('/${repo(nightly)}/releases/download/$tag/yt-dlp.exe'), tmp);
    if (tmp.lengthSync() < minBinaryBytes) {
      final size = tmp.lengthSync();
      await tmp.delete();
      throw ToolInstallException('Downloaded yt-dlp.exe too small ($size bytes)');
    }
    final target = File(_ytdlp);
    final backup = File('$_ytdlp.old');
    if (backup.existsSync()) await backup.delete();
    if (target.existsSync()) await target.rename(backup.path);
    await tmp.rename(target.path);
    final v = await _runVersion();
    if (v == null) {
      await target.delete();
      if (backup.existsSync()) await backup.rename(target.path);
      throw ToolInstallException('New yt-dlp $tag did not start; kept the previous version');
    }
    if (backup.existsSync()) await backup.delete().catchError((Object _) => backup);
    _writeState({..._readState(), 'tag': tag, 'version': v});
  }

  /// Unzips [names] from the zip at [url] into [into].
  Future<void> _installFromZip(Uri url, Set<String> names, String into) async {
    final work = Directory('$_dir${_sep}unpack-${DateTime.now().microsecondsSinceEpoch}');
    await work.create(recursive: true);
    try {
      final zip = File('${work.path}${_sep}archive.zip');
      await _download(url, zip);
      final out = await Directory('${work.path}${_sep}out').create();
      await _unzip(zip.path, out.path);
      await Directory(into).create(recursive: true);
      final found = findFiles(out.listSync(recursive: true).whereType<File>().map((f) => f.path), names);
      if (found.length != names.length) throw ToolInstallException('Missing ${names.difference(found.keys.toSet())} in $url');
      for (final e in found.entries) {
        final dest = File('$into$_sep${e.key}');
        if (dest.existsSync()) await dest.delete();
        await File(e.value).rename(dest.path);
      }
    } finally {
      await work.delete(recursive: true).catchError((Object _) => work);
    }
  }

  static Future<void> _download(Uri url, File to) async {
    final client = HttpClient()..userAgent = 'Toomu';
    try {
      final req = await client.getUrl(url);
      final res = await req.close();
      if (res.statusCode != 200) throw ToolInstallException('Download failed: HTTP ${res.statusCode} for $url');
      await res.pipe(to.openWrite());
    } finally {
      client.close(force: true);
    }
  }

  static String repo(bool nightly) => nightly ? 'yt-dlp/yt-dlp-nightly-builds' : 'yt-dlp/yt-dlp';

  /// Latest release tag from the `/releases/latest` redirect.
  Future<String> _latestTag({required bool nightly}) async {
    final client = HttpClient()..userAgent = 'Toomu';
    try {
      final req = await client.headUrl(_github.resolve('/${repo(nightly)}/releases/latest'));
      req.followRedirects = false;
      final res = await req.close();
      await res.drain<void>();
      final tag = tagFromLocation(res.headers.value(HttpHeaders.locationHeader));
      if (tag == null) throw ToolInstallException('GitHub returned HTTP ${res.statusCode} without a release tag');
      return tag;
    } finally {
      client.close(force: true);
    }
  }

  /// "…/releases/tag/2026.10.26" → "2026.10.26".
  @visibleForTesting
  static String? tagFromLocation(String? location) {
    if (location == null || !location.contains('/tag/')) return null;
    final tag = Uri.decodeComponent(location.substring(location.lastIndexOf('/tag/') + 5));
    return tag.isEmpty ? null : tag;
  }

  /// The first file per name (case-insensitive) among [paths].
  @visibleForTesting
  static Map<String, String> findFiles(Iterable<String> paths, Set<String> names) {
    final found = <String, String>{};
    for (final p in paths) {
      final name = p.split(RegExp(r'[\\/]')).last.toLowerCase();
      for (final n in names) {
        if (n.toLowerCase() == name) found.putIfAbsent(n, () => p);
      }
    }
    return found;
  }

  /// The command line for one run: [args] with the URL last ('' = none).
  /// Android-only options are dropped (aria2c isn't installed here), and
  /// FFmpeg / Deno are pointed at when they are there.
  @visibleForTesting
  static List<String> commandLine(List<String> args, {String? ffmpegDir, String? deno}) {
    final url = args.isEmpty ? '' : args.last;
    return [
      '--encoding', 'utf-8',
      if (ffmpegDir != null) ...['--ffmpeg-location', ffmpegDir],
      if (deno != null) ...['--js-runtimes', 'deno:$deno'],
      for (final a in args.isEmpty ? const <String>[] : args.sublist(0, args.length - 1))
        if (!a.startsWith('--toomu-aria2c=')) a,
      if (url.isNotEmpty) url,
    ];
  }

  /// Lookups don't need FFmpeg, so they don't wait for it to download.
  @visibleForTesting
  static bool isLookup(List<String> args) =>
      args.contains('--skip-download') || args.contains('-J') || args.contains('--dump-single-json');

  Future<YtDlpResult> run(String id, List<String> args) async {
    await _ensure();
    if (!isLookup(args) && !_hasFfmpeg) {
      await (_extras ??= _installExtras()).timeout(const Duration(minutes: 10), onTimeout: () {});
    }
    await _updating?.catchError((Object _) {});
    final ffmpeg = _hasFfmpeg ? _ffmpegDir : null;
    final deno = File(_deno).existsSync() ? _deno : null;
    _canceled.remove(id);
    final process = await _launch(_ytdlp, commandLine(args, ffmpegDir: ffmpeg, deno: deno));
    _running[id] = process;
    final out = StringBuffer();
    final err = StringBuffer();
    Future<void> collect(Stream<List<int>> s, StringBuffer into) => s
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen((line) {
          into.writeln(line);
          // Skip huge lines (the info JSON): only progress/status lines matter.
          if (line.length <= 2000) _progress.add((id: id, line: line));
        })
        .asFuture<void>()
        .catchError((Object _) {});
    final reading = [collect(process.stdout, out), collect(process.stderr, err)];
    final code = await process.exitCode;
    await Future.wait(reading);
    _running.remove(id);
    if (_canceled.remove(id)) return const YtDlpResult(exitCode: -1, out: '', err: '', canceled: true);
    return YtDlpResult(exitCode: code, out: out.toString(), err: err.toString());
  }

  /// Stops run [id] with everything it started (Python, FFmpeg).
  Future<bool> cancel(String id) async {
    final p = _running[id];
    if (p == null) return false;
    _canceled.add(id);
    await _killTree(p);
    return true;
  }
}

/// Starts [exe] with [args] (tests run a stand-in script instead).
typedef ToolLauncher = Future<Process> Function(String exe, List<String> args);

/// yt-dlp, FFmpeg or Deno couldn't be downloaded or started.
class ToolInstallException implements IOException {
  ToolInstallException(this.message);

  final String message;

  @override
  String toString() => message;
}
