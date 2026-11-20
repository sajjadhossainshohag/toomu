import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';

import 'host_os.dart';

/// Starts a program (tests record the call instead).
@visibleForTesting
Future<Object?> Function(String exe, List<String> args) startProcess = Process.start;

/// Starts a program that outlives Toomu, e.g. the update installer (tests record the call instead).
@visibleForTesting
Future<Object?> Function(String exe, List<String> args) startDetached =
    (exe, args) => Process.start(exe, args, mode: ProcessStartMode.detached);

/// Starts [exe] so it keeps running after Toomu exits.
Future<void> runDetached(String exe, List<String> args) async {
  await startDetached(exe, args);
}

/// Windows: opens a web link in the default browser.
Future<void> openUrl(String url) async {
  await startProcess('explorer', [url]);
}

/// Opens a file with its default app (open_filex on Android, which has no
/// Windows side).
@visibleForTesting
Future<Object?> Function(String path) openWithAndroid = OpenFilex.open;

/// Windows: [path] with backslashes (Explorer misreads forward slashes).
String windowsPath(String path) => path.replaceAll('/', r'\');

/// Opens a file with its default app, or a folder in Explorer (Windows).
Future<void> openInExplorer(String path) async {
  await startProcess('explorer', [windowsPath(path)]);
}

/// Opens a finished download with the app the system picks for it.
Future<void> openFile(String path) async {
  if (HostOs.isWindows) return openInExplorer(path);
  final result = await openWithAndroid(path);
  if (result is OpenResult && result.type != ResultType.done) throw FileSystemException(result.message, path);
}
