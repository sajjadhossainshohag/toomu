import '../modules/browser/views/downloads_sheet.dart';
import '../services/download_service.dart';
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
  Future<void> openDownload(Uri uri) => startDownload(uri.toString());

  static Future<void> startDownload(
    String url, {
    String? fileName,
    int size = 0,
    String? pageUrl,
    Map<String, String> headers = const {},
    String? mimeType,
  }) async {
    final uri = Uri.parse(url);
    final name = (fileName?.trim().isNotEmpty ?? false)
        ? fileName!.trim()
        : Uri.decodeComponent(uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? 'file');
    await DownloadService.to.enqueueDirect(
      url: url,
      fileName: name,
      size: size,
      pageUrl: pageUrl,
      headers: headers,
      mimeType: mimeType,
    );
    showDownloadStarted(name);
  }
}
