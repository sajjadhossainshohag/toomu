import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';

import 'host_os.dart';

/// Starts a program (tests record the call instead).
@visibleForTesting
Future<Object?> Function(String exe, List<String> args) startProcess = Process.start;

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
  await openWithAndroid(path);
}
