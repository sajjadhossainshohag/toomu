import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/utils/formatters.dart';

/// What a long-pressed image on a page offers (Chrome's image menu).
enum ImageAction {
  open('Open image in new tab'),
  preview('Preview image'),
  copy('Copy image'),
  copyLink('Copy image link'),
  download('Download image'),
  lens('Search image with Google Lens'),
  share('Share image');

  const ImageAction(this.label);

  final String label;
}

/// The image the user long-pressed, and what the page says about it.
class PageImage {
  const PageImage({required this.src, this.alt = '', this.pageUrl = '', this.headers = const {}});

  /// `http(s):`, `data:` (inline) or `blob:` (made by the page's script).
  final String src;

  /// The image's alt text or title, if the page gave one.
  final String alt;
  final String pageUrl;

  /// User-Agent / Referer / Cookie to fetch it like the page did (sites
  /// often refuse images requested without their own page as Referer).
  final Map<String, String> headers;

  String get _scheme => src.split(':').first.toLowerCase();

  /// A link anyone can open (vs. bytes that only exist inside this page).
  bool get isWebLink => _scheme == 'http' || _scheme == 'https';
  bool get isInline => _scheme == 'data';
  bool get isBlob => _scheme == 'blob';

  /// Header line of the menu: the alt text, else the file's name.
  String get title {
    final a = alt.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (a.isNotEmpty) return a;
    if (!isWebLink) return 'Image';
    final segments = Uri.tryParse(src)?.pathSegments.where((s) => s.isNotEmpty) ?? const <String>[];
    if (segments.isEmpty) return Uri.tryParse(src)?.host ?? 'Image';
    try {
      return Uri.decodeComponent(segments.last);
    } catch (_) {
      return segments.last;
    }
  }
}

/// The menu's rows, in Chrome's order. Opening, Lens and copying the link
/// need a link outside the page, so inline and blob images don't get them.
/// [canCopyImage]: the clipboard takes images (Android).
List<ImageAction> imageActions(PageImage image, {required bool canCopyImage}) => [
  if (image.isWebLink) ImageAction.open,
  ImageAction.preview,
  if (canCopyImage) ImageAction.copy,
  if (image.isWebLink) ImageAction.copyLink,
  ImageAction.download,
  if (image.isWebLink) ImageAction.lens,
  ImageAction.share,
];

/// Google Lens for an image on the web.
Uri lensUrl(String src) => Uri.https('lens.google.com', '/uploadbyurl', {'url': src});

/// Image file types by MIME type.
const _imageExt = {
  'image/jpeg': 'jpg',
  'image/jpg': 'jpg',
  'image/pjpeg': 'jpg',
  'image/png': 'png',
  'image/gif': 'gif',
  'image/webp': 'webp',
  'image/avif': 'avif',
  'image/bmp': 'bmp',
  'image/svg+xml': 'svg',
  'image/x-icon': 'ico',
  'image/vnd.microsoft.icon': 'ico',
  'image/heic': 'heic',
};

const _knownExt = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'avif', 'bmp', 'svg', 'ico', 'heic'};

/// MIME type for a file extension (for sharing and the clipboard).
String imageMimeFor(String ext) => switch (ext.toLowerCase()) {
  'jpg' || 'jpeg' => 'image/jpeg',
  'svg' => 'image/svg+xml',
  'ico' => 'image/x-icon',
  final e => 'image/$e',
};

/// File name for saving [image]: its alt text (else the link's name) and
/// an image extension, from [mimeType] first (the server knows best), then
/// the link, else jpg.
String imageFileName(PageImage image, {String? mimeType}) {
  final mime = mimeType?.split(';').first.trim().toLowerCase();
  String? linkExt;
  var linkBase = '';
  if (image.isWebLink) {
    final last = Uri.tryParse(image.src)?.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? '';
    final dot = last.lastIndexOf('.');
    if (dot > 0) {
      final e = last.substring(dot + 1).toLowerCase();
      if (_knownExt.contains(e)) {
        linkExt = e == 'jpeg' ? 'jpg' : e;
        linkBase = last.substring(0, dot);
      }
    }
    if (linkBase.isEmpty) linkBase = last;
  }
  final ext = _imageExt[mime] ?? linkExt ?? 'jpg';
  final alt = image.alt.trim();
  final raw = alt.isNotEmpty ? alt : (linkBase.isNotEmpty ? _decoded(linkBase) : 'image');
  return '${Formatters.fileName(raw, maxBytes: 120)}.$ext';
}

String _decoded(String s) {
  try {
    return Uri.decodeComponent(s);
  } catch (_) {
    return s;
  }
}

/// Bytes and type of a `data:` image; null if it isn't one or is broken.
({Uint8List bytes, String mimeType})? decodeDataImage(String src) {
  if (!src.toLowerCase().startsWith('data:')) return null;
  try {
    final data = UriData.parse(src);
    return (bytes: data.contentAsBytes(), mimeType: data.mimeType);
  } catch (_) {
    return null;
  }
}

/// Script that finds the alt text of the image at `src` in the page
/// (`callAsyncJavaScript` passes `src`; no string building, no injection).
const imageAltJs = '''
var list = document.images;
for (var i = 0; i < list.length; i++) {
  var m = list[i];
  if (m.currentSrc === src || m.src === src) return String(m.alt || m.title || '').trim().slice(0, 300);
}
return '';
''';

/// Script that reads a `blob:` image made by the page as a data URL.
const blobToDataUrlJs = '''
var r = await fetch(src);
var b = await r.blob();
return await new Promise(function (ok, fail) {
  var f = new FileReader();
  f.onload = function () { ok(f.result); };
  f.onerror = function () { fail(f.error); };
  f.readAsDataURL(b);
});
''';

/// The picture's bytes and type, fetched the way the page fetched it:
/// web links with the page's headers, inline images decoded, blob images
/// read inside the page by [readBlob] (returns a data URL).
Future<({Uint8List bytes, String mimeType})> loadImageBytes(
  PageImage image, {
  required Dio dio,
  required Future<String?> Function(String src) readBlob,
}) async {
  if (image.isInline) {
    return decodeDataImage(image.src) ?? (throw const FormatException('Broken inline image'));
  }
  if (image.isBlob) {
    final data = await readBlob(image.src);
    final decoded = data == null ? null : decodeDataImage(data);
    return decoded ?? (throw const FormatException("The page didn't hand over the image"));
  }
  final r = await dio.get<List<int>>(
    image.src,
    options: Options(responseType: ResponseType.bytes, headers: image.headers),
  );
  final mime = (r.headers.value('content-type') ?? '').split(';').first.trim();
  return (bytes: Uint8List.fromList(r.data ?? const []), mimeType: mime.isEmpty ? 'image/jpeg' : mime);
}
