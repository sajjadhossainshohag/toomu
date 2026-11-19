import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../core/utils/subtitles.dart';
import '../data/models/download_task.dart';
import 'storage_service.dart';

class PrivateVault {
  PrivateVault(this.dir, this._store);

  static Future<PrivateVault> open() async => PrivateVault(
        await Directory('${(await getApplicationSupportDirectory()).path}/private').create(recursive: true),
        StorageService.to,
      );

  static const pinKey = 'privatePin';
  static const _triesKey = 'privatePinTries';
  static const _lockoutsKey = 'privatePinLockouts';
  static const _lockKey = 'privatePinLock';
  static const maxTries = 5;
  static const lockWaits = [
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(hours: 1),
  ];
  static const _video = {'mp4', 'mkv', 'webm', 'mov', '3gp', 'avi', 'm4v', 'flv', 'ts'};
  static const _audio = {'mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'oga', 'opus', 'wma'};

  final Directory dir;
  final StorageService _store;
  @visibleForTesting
  DateTime Function() now = DateTime.now;
  @visibleForTesting
  Future<({int? boot, Duration elapsed})?> Function() uptime = _deviceUptime;
  static Future<void> _busy = Future.value();

  bool get hasPin => _store.read<String>(pinKey) != null;

  Future<void> setPin(String pin) async {
    final salt = base64Url.encode([for (var i = 0; i < 16; i++) Random.secure().nextInt(256)]);
    await Future.wait([_store.write(pinKey, '$salt:${_hash(salt, pin)}'), resetTries()]);
  }

  Future<Duration> lockLeft() async {
    final lock = _store.read<Map<dynamic, dynamic>>(_lockKey);
    if (lock == null) return Duration.zero;
    final wait = Duration(milliseconds: lock['wait'] as int);
    final up = await uptime();
    final from = lock['uptime'] as int?;
    // The wall clock only where there's no uptime (Windows): moving it forward would end the lock.
    final elapsed = up == null
        ? now().difference(DateTime.fromMillisecondsSinceEpoch(lock['at'] as int))
        : up.boot != null && up.boot == lock['boot'] && from != null
            ? up.elapsed - Duration(milliseconds: from)
            : null;
    if (elapsed == null || elapsed.isNegative) {
      // Uptime restarts with the phone and a wall clock can be set back: the full wait starts again from now.
      await _lock(wait);
      return wait;
    }
    if (elapsed < wait) return wait - elapsed;
    await _store.remove(_lockKey);
    return Duration.zero;
  }

  Future<void> _lock(Duration wait) async {
    final up = await uptime();
    await _store.write(_lockKey, {
      'wait': wait.inMilliseconds,
      'at': now().millisecondsSinceEpoch,
      'boot': up?.boot,
      'uptime': up?.elapsed.inMilliseconds,
    });
  }

  static Future<({int? boot, Duration elapsed})?> _deviceUptime() async {
    if (!Platform.isAndroid) return null;
    try {
      final m = await const MethodChannel('toomu/video').invokeMapMethod<String, Object?>('clock');
      final ms = m?['elapsed'] as int?;
      return ms == null ? null : (boot: m!['boot'] as int?, elapsed: Duration(milliseconds: ms));
    } on PlatformException catch (e) {
      debugPrint('[Private] clock: $e');
      return null;
    }
  }

  Future<bool> tryPin(String pin) async {
    if (await lockLeft() > Duration.zero) return false;
    if (checkPin(pin)) {
      await resetTries();
      return true;
    }
    final tries = (_store.read<int>(_triesKey) ?? 0) + 1;
    if (tries < maxTries) {
      await _store.write(_triesKey, tries);
      return false;
    }
    final lockouts = _store.read<int>(_lockoutsKey) ?? 0;
    await Future.wait([
      _store.write(_triesKey, 0),
      _store.write(_lockoutsKey, lockouts + 1),
      _lock(lockWaits[min(lockouts, lockWaits.length - 1)]),
    ]);
    return false;
  }

  Future<void> resetTries() => Future.wait([_triesKey, _lockoutsKey, _lockKey].map(_store.remove));

  bool checkPin(String pin) {
    final saved = _store.read<String>(pinKey);
    final i = saved?.indexOf(':') ?? -1;
    return i > 0 && _hash(saved!.substring(0, i), pin) == saved.substring(i + 1);
  }

  static String _hash(String salt, String pin) => sha256.convert(utf8.encode('$salt$pin')).toString();

  static DownloadKind kindOf(String path) {
    final ext = path.substring(path.lastIndexOf('.') + 1).toLowerCase();
    if (_video.contains(ext)) return DownloadKind.video;
    return _audio.contains(ext) ? DownloadKind.audio : DownloadKind.file;
  }

  List<File> files() {
    // Rebuilt with "/": Windows lists with "\", which the subtitle lookup doesn't split on.
    final all = [
      for (final f in dir.listSync().whereType<File>())
        if (!f.path.endsWith('.part')) File('${dir.path}/${f.uri.pathSegments.last}'),
    ];
    final subs = {
      for (final f in all)
        if (kindOf(f.path) == DownloadKind.video) ...Subtitles.sidecarsOf(f.path),
    };
    return all.where((f) => !subs.contains(f.path)).toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
  }

  Future<List<String>> moveManyIn(List<String> paths, Future<void> Function() deleteOriginals) =>
      _oneAtATime(() => _moveManyIn(paths, deleteOriginals));

  Future<List<String>> _moveManyIn(List<String> paths, Future<void> Function() deleteOriginals) async {
    final copies = <String, List<String>>{};
    try {
      for (final p in paths) {
        copies[p] = await _transfer(p, dir.path, copy: true);
      }
    } catch (_) {
      await _deleteAll([for (final c in copies.values) ...c]);
      rethrow;
    }
    // Not rethrown: some originals may be gone even when this throws, and their copies must stay.
    try {
      await deleteOriginals();
    } catch (e) {
      debugPrint('[Private] deleting originals failed: $e');
    }
    final moved = <String>[];
    for (final MapEntry(key: path, value: copied) in copies.entries) {
      // Checked on disk: Android's dialog may be declined, and a file left by an earlier install of Toomu can't be deleted on Android 11+.
      if (File(path).existsSync()) {
        await _deleteAll(copied);
      } else {
        moved.add(path);
        await _deleteAll(Subtitles.sidecarsOf(path));
      }
    }
    return moved;
  }

  Future<String> moveOut(File file, String toDir) => _oneAtATime(() async {
        await Directory(toDir).create(recursive: true);
        return (await _transfer(file.path, toDir, copy: false)).first;
      });

  static Future<T> _oneAtATime<T>(Future<T> Function() job) {
    // A free name is picked before a long copy: two moves at once could pick the same one.
    final run = _busy.then((_) => job());
    _busy = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<void> delete(File file) => _deleteAll([file.path, ...Subtitles.sidecarsOf(file.path)]);

  static Future<void> _deleteAll(List<String> paths) async {
    for (final p in paths) {
      try {
        await File(p).delete();
      } on FileSystemException {
        // Already gone.
      }
    }
  }

  static Future<List<String>> _transfer(String path, String toDir, {required bool copy}) async {
    final name = path.substring(path.lastIndexOf(RegExp(r'[/\\]')) + 1);
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    var target = '$toDir/$base$ext';
    for (var n = 2; File(target).existsSync(); n++) {
      target = '$toDir/$base ($n)$ext';
    }
    final newBase = target.substring(toDir.length + 1, target.length - ext.length);
    final sources = [path, ...Subtitles.sidecarsOf(path)];
    final done = <String>[];
    var to = target;
    try {
      for (final p in sources) {
        to = p == path ? target : '$toDir/$newBase${p.substring(path.length - ext.length)}';
        // Written under a temporary name: a copy cut short (full storage, app killed) never looks like a whole file.
        if (copy || !await _renamed(File(p), to)) await (await File(p).copy('$to.part')).rename(to);
        done.add(to);
      }
    } catch (_) {
      await _deleteAll(['$to.part', if (copy) ...done]);
      rethrow;
    }
    if (!copy) await _deleteAll(sources.where((p) => File(p).existsSync()).toList());
    return done;
  }

  static Future<bool> _renamed(File f, String to) async {
    try {
      await f.rename(to);
      return true;
    } on FileSystemException {
      // Across storage volumes (app storage → the Download folder): the caller copies instead.
      return false;
    }
  }
}
