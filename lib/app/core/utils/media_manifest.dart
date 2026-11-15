import 'dart:convert';

class StreamVariant {
  const StreamVariant({
    required this.url,
    this.width = 0,
    this.height = 0,
    this.bandwidth = 0,
    this.codecs = '',
    this.audioGroup = '',
  });

  final String url;
  final int width;
  final int height;
  final int bandwidth;
  final String codecs;
  final String audioGroup;
}

class HlsRendition {
  const HlsRendition({required this.type, required this.group, required this.url, this.isDefault = false});

  final String type;
  final String group;
  final String url;
  final bool isDefault;
}

class ManifestInfo {
  const ManifestInfo({
    this.variants = const [],
    this.renditions = const [],
    this.duration,
    this.protected = false,
    this.audioOnly = false,
  });

  final List<StreamVariant> variants;
  final List<HlsRendition> renditions;
  final Duration? duration;
  final bool protected;
  final bool audioOnly;
}

abstract class MediaManifest {
  static final _hlsAttr = RegExp(r'([A-Z0-9-]+)=("[^"]*"|[^,]*)');
  static final _xmlAttr = RegExp(r'([A-Za-z:]+)="([^"]*)"');
  static final _videoCodec = RegExp(r'avc|hvc|hev|vp0?[89]|av01|dvh', caseSensitive: false);
  static final _digits = RegExp(r'\d+');
  static const _heights = {144, 180, 220, 240, 270, 360, 480, 540, 576, 720, 1080, 1440, 2160, 4320};

  static ManifestInfo parseHls(String text, Uri base) {
    final lines = const LineSplitter()
        .convert(text)
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final variants = <StreamVariant>[];
    final renditions = <HlsRendition>[];
    var seconds = 0.0;
    var protected = false;
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      if (l.startsWith('#EXT-X-STREAM-INF:')) {
        if (i + 1 >= lines.length || lines[i + 1].startsWith('#')) continue;
        final a = _attrs(l.substring(l.indexOf(':') + 1));
        final res = (a['RESOLUTION'] ?? '').split('x');
        variants.add(StreamVariant(
          url: base.resolve(lines[++i]).toString(),
          width: int.tryParse(res.first) ?? 0,
          height: res.length > 1 ? int.tryParse(res[1]) ?? 0 : 0,
          bandwidth: int.tryParse(a['AVERAGE-BANDWIDTH'] ?? a['BANDWIDTH'] ?? '') ?? 0,
          codecs: a['CODECS'] ?? '',
          audioGroup: a['AUDIO'] ?? '',
        ));
      } else if (l.startsWith('#EXT-X-MEDIA:')) {
        final a = _attrs(l.substring(l.indexOf(':') + 1));
        final uri = a['URI'];
        if (uri != null && uri.isNotEmpty) {
          renditions.add(HlsRendition(
            type: a['TYPE'] ?? '',
            group: a['GROUP-ID'] ?? '',
            url: base.resolve(uri).toString(),
            isDefault: a['DEFAULT'] == 'YES',
          ));
        }
      } else if (l.startsWith('#EXTINF:')) {
        seconds += double.tryParse(l.substring(8).split(',').first) ?? 0;
      } else if (l.startsWith('#EXT-X-KEY:') || l.startsWith('#EXT-X-SESSION-KEY:')) {
        final a = _attrs(l.substring(l.indexOf(':') + 1));
        final format = a['KEYFORMAT'];
        // AES-128 with a plain key is normal encryption; anything else is DRM.
        if ((a['METHOD'] ?? '').startsWith('SAMPLE-AES') || (format != null && format != 'identity')) {
          protected = true;
        }
      }
    }
    final audioOnly = variants.isNotEmpty &&
        variants.every((v) => v.codecs.isNotEmpty && !_videoCodec.hasMatch(v.codecs));
    return ManifestInfo(
      variants: audioOnly ? _bestFirst(variants) : _onePerHeight(variants),
      renditions: renditions,
      duration: seconds > 0 ? Duration(milliseconds: (seconds * 1000).round()) : null,
      protected: protected,
      audioOnly: audioOnly,
    );
  }

  static ManifestInfo parseDash(String xml, String url) {
    // shortcut: regex, not an XML parser; enough for Representation attributes, upgrade if MPDs need inheritance.
    final variants = <StreamVariant>[];
    var audio = false;
    for (final m in RegExp(r'<Representation\b([^>]*)>').allMatches(xml)) {
      final a = {for (final x in _xmlAttr.allMatches(m.group(1)!)) x.group(1)!: x.group(2)!};
      final height = int.tryParse(a['height'] ?? '') ?? 0;
      if (height <= 0) {
        audio = true;
        continue;
      }
      variants.add(StreamVariant(
        url: url, // yt-dlp picks the DASH quality from the manifest
        width: int.tryParse(a['width'] ?? '') ?? 0,
        height: height,
        bandwidth: int.tryParse(a['bandwidth'] ?? '') ?? 0,
        codecs: a['codecs'] ?? '',
      ));
    }
    final duration = RegExp(r'mediaPresentationDuration="([^"]+)"').firstMatch(xml)?.group(1);
    return ManifestInfo(
      variants: _onePerHeight(variants),
      duration: duration == null ? null : isoDuration(duration),
      protected: xml.contains('<ContentProtection'),
      audioOnly: variants.isEmpty && audio,
    );
  }

  static Duration? isoDuration(String s) {
    final m = RegExp(r'^P(?:(\d+(?:\.\d+)?)D)?(?:T(?:(\d+(?:\.\d+)?)H)?(?:(\d+(?:\.\d+)?)M)?(?:(\d+(?:\.\d+)?)S)?)?$')
        .firstMatch(s.trim());
    if (m == null) return null;
    double part(int i) => double.tryParse(m.group(i) ?? '') ?? 0;
    final seconds = part(1) * 86400 + part(2) * 3600 + part(3) * 60 + part(4);
    return seconds > 0 ? Duration(milliseconds: (seconds * 1000).round()) : null;
  }

  static String segmentKey(String url) {
    final u = Uri.tryParse(url);
    return u == null ? url : '${u.host}${u.path.replaceAll(_digits, '#')}';
  }

  static bool looksLikeSegments(List<String> urls) {
    if (urls.length < 4) return false;
    // Quality ladders (DASH_720.mp4, DASH_480.mp4) share a key too.
    final numbers = [
      for (final u in urls)
        [for (final m in _digits.allMatches(Uri.tryParse(u)?.path ?? u)) int.tryParse(m.group(0)!) ?? -1],
    ];
    final differing = <int>{};
    for (var i = 0; i < numbers.first.length; i++) {
      final values = {for (final n in numbers) if (i < n.length) n[i]};
      if (values.length > 1) differing.addAll(values);
    }
    return differing.isNotEmpty && !differing.every(_heights.contains);
  }

  static bool sameMedia(String oldUrl, int oldSize, String newUrl, int newSize) {
    // Equal sizes only prove it for large files; small ones collide.
    if (oldSize > 1 << 20 && oldSize == newSize) return true;
    final a = Uri.tryParse(oldUrl);
    final b = Uri.tryParse(newUrl);
    if (a == null || b == null) return false;
    if (a.path.length > 1 && a.path == b.path) return true;
    final name = a.pathSegments.isEmpty ? '' : a.pathSegments.last;
    return name.contains('.') && b.pathSegments.isNotEmpty && b.pathSegments.last == name;
  }

  static Map<String, String> attributes(String s) => _attrs(s);

  static Map<String, String> _attrs(String s) => {
        for (final m in _hlsAttr.allMatches(s)) m.group(1)!: m.group(2)!.replaceAll('"', ''),
      };

  static List<StreamVariant> _bestFirst(List<StreamVariant> v) =>
      [...v]..sort((a, b) => b.bandwidth.compareTo(a.bandwidth));

  static List<StreamVariant> _onePerHeight(List<StreamVariant> variants) {
    final video = variants.where((v) => v.height > 0).toList();
    if (video.isEmpty) return _bestFirst(variants).take(1).toList();
    final best = <int, StreamVariant>{};
    for (final v in video) {
      final have = best[v.height];
      // AAC plays everywhere; AC-3/E-AC-3 groups often carry a higher bitrate.
      final aac = v.codecs.contains('mp4a'), haveAac = have?.codecs.contains('mp4a') ?? false;
      if (have == null || (aac && !haveAac) || (aac == haveAac && v.bandwidth > have.bandwidth)) {
        best[v.height] = v;
      }
    }
    return best.values.toList()..sort((a, b) => b.height.compareTo(a.height));
  }
}
