import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../core/utils/formatters.dart';
import '../services/download_service.dart';
import '../widgets/option_sheet.dart';
import 'media_extractor.dart';

/// Links that point straight at a media/file (…/song.mp3, …/clip.mp4).
/// 1DM-style: downloads the URL as-is.
class DirectFileExtractor extends MediaExtractor {
  const DirectFileExtractor();

  static const extensions = <String>{
    'mp4', 'mkv', 'webm', 'mov', '3gp', 'avi', 'm4v', //
    'mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'opus',
    'zip', 'rar', '7z', 'pdf', 'apk', 'epub',
  };

  @override
  String get id => 'direct';

  @override
  String get name => 'File';

  @override
  bool canHandle(Uri uri) {
    if (!uri.isScheme('http') && !uri.isScheme('https')) return false;
    final last = uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? '';
    final dot = last.lastIndexOf('.');
    return dot > 0 && extensions.contains(last.substring(dot + 1).toLowerCase());
  }

  @override
  Future<void> openDownload(Uri uri) => confirmAndDownload(uri.toString());

  /// Asks before downloading (also used for the browser's download events,
  /// which come with a server-suggested name and size).
  static Future<void> confirmAndDownload(String url, {String? fileName, int size = 0}) async {
    final uri = Uri.parse(url);
    final name = (fileName?.trim().isNotEmpty ?? false)
        ? fileName!.trim()
        : Uri.decodeComponent(uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? 'file');
    final ok = await showOptionSheet<bool>(
      title: 'Download file?',
      options: <SheetOption<bool>>[
        SheetOption(
          value: true,
          label: name,
          subtitle: [uri.host, if (size > 0) Formatters.bytes(size)].join(' • '),
          icon: Icons.download_rounded,
        ),
      ],
    );
    if (ok != true) return;
    await DownloadService.to.enqueueDirect(url: url, fileName: name, size: size);
    Get.snackbar('Download started', name, duration: const Duration(seconds: 2));
  }
}
