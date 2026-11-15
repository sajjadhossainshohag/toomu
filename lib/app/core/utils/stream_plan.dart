import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import 'media_manifest.dart';

enum TrackContainer { fmp4, ts, aac }

class SegmentRef {
  const SegmentRef(this.url, {this.offset, this.length, this.keyUrl, this.iv});

  final String url;
  final int? offset;
  final int? length;

  // AES-128 (HLS); the IV defaults to the media sequence number.
  final String? keyUrl;
  final Uint8List? iv;

  String? get range => offset == null || length == null ? null : 'bytes=$offset-${offset! + length! - 1}';
}

// Pieces that decode as one stream: a new run starts at an HLS
// discontinuity, a new init section, or a new DASH period.
class StreamRun {
  const StreamRun({required this.segments, this.init, this.container = TrackContainer.fmp4});

  final SegmentRef? init;
  final List<SegmentRef> segments;
  final TrackContainer container;

  List<SegmentRef> get parts => [?init, ...segments];

  String get extension => switch (container) {
    TrackContainer.fmp4 => 'mp4',
    TrackContainer.ts => 'ts',
    TrackContainer.aac => 'aac',
  };
}

class StreamTrack {
  const StreamTrack(this.runs);

  final List<StreamRun> runs;

  int get partCount => runs.fold(0, (n, r) => n + r.parts.length);
}

class StreamPlanException implements Exception {
  const StreamPlanException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class StreamPlanner {
  static const live = StreamPlanException("This is a live stream; it can't be downloaded.");
  static const drm = StreamPlanException("This video is DRM-protected and can't be downloaded.");
  static const webmOnly = StreamPlanException(
    "This stream only offers WebM, which Toomu can't save on iPhone yet.",
  );

  static final _fmp4Piece = RegExp(r'\.(m4s|mp4|m4v|m4a|cmfv|cmfa)$');
  static final _aacPiece = RegExp(r'\.(aac|adts)$');
  static final _template = RegExp(r'\$(RepresentationID|Number|Bandwidth|Time)(?:%0(\d+)d)?\$');
  static final _range = RegExp(r'^(\d+)-(\d+)$');

  static StreamTrack hlsMedia(String text, Uri base) {
    final lines = const LineSplitter()
        .convert(text)
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (!lines.contains('#EXT-X-ENDLIST')) throw live;
    var sequence = 0;
    String? keyUrl;
    Uint8List? keyIv;
    SegmentRef? init;
    (int, int?)? range;
    final nextOffset = <String, int>{};
    final runs = <StreamRun>[];
    var segments = <SegmentRef>[];
    var runInit = init;

    void closeRun() {
      if (segments.isEmpty) return;
      runs.add(_run(runInit, segments));
      segments = <SegmentRef>[];
    }

    for (final l in lines) {
      if (l.startsWith('#EXT-X-MEDIA-SEQUENCE:')) {
        sequence = int.tryParse(l.substring(22)) ?? 0;
      } else if (l == '#EXT-X-DISCONTINUITY') {
        closeRun();
      } else if (l.startsWith('#EXT-X-KEY:')) {
        final a = MediaManifest.attributes(l.substring(11));
        final method = a['METHOD'] ?? 'NONE';
        if (method == 'NONE') {
          keyUrl = null;
        } else if (method == 'AES-128' && (a['KEYFORMAT'] ?? 'identity') == 'identity' && a['URI'] != null) {
          keyUrl = base.resolve(a['URI']!).toString();
          keyIv = _hex(a['IV']);
        } else {
          throw drm;
        }
      } else if (l.startsWith('#EXT-X-MAP:')) {
        final a = MediaManifest.attributes(l.substring(11));
        final r = _byteRange(a['BYTERANGE']);
        // RFC 8216 4.3.2.5: an init section is encrypted only by a key that
        // precedes it, and that key must then carry an IV.
        final encrypted = keyUrl != null && keyIv != null;
        final next = SegmentRef(
          base.resolve(a['URI'] ?? '').toString(),
          offset: r == null ? null : r.$2 ?? 0,
          length: r?.$1,
          keyUrl: encrypted ? keyUrl : null,
          iv: encrypted ? keyIv : null,
        );
        if (segments.isNotEmpty && (runInit?.url != next.url || runInit?.range != next.range)) closeRun();
        init = next;
        runInit = next;
      } else if (l.startsWith('#EXT-X-BYTERANGE:')) {
        range = _byteRange(l.substring(17));
      } else if (!l.startsWith('#')) {
        final url = base.resolve(l).toString();
        final r = range;
        int? offset;
        if (r != null) {
          offset = r.$2 ?? nextOffset[url] ?? 0;
          nextOffset[url] = offset + r.$1;
        }
        if (segments.isEmpty) runInit = init;
        segments.add(SegmentRef(
          url,
          offset: offset,
          length: r?.$1,
          keyUrl: keyUrl,
          iv: keyUrl == null ? null : keyIv ?? _sequenceIv(sequence),
        ));
        sequence++;
        range = null;
      }
    }
    closeRun();
    if (runs.isEmpty) throw const StreamPlanException('The stream has no pieces to download.');
    return StreamTrack(runs);
  }

  static StreamRun _run(SegmentRef? init, List<SegmentRef> segments) {
    final path = Uri.parse(segments.first.url).path.toLowerCase();
    return StreamRun(
      init: init,
      segments: segments,
      container: init != null || _fmp4Piece.hasMatch(path)
          ? TrackContainer.fmp4
          : _aacPiece.hasMatch(path)
          ? TrackContainer.aac
          : TrackContainer.ts,
    );
  }

  static StreamVariant pickVariant(List<StreamVariant> bestFirst, int maxHeight) {
    if (maxHeight <= 0) return bestFirst.first;
    for (final v in bestFirst) {
      if (v.height <= maxHeight) return v;
    }
    return bestFirst.last;
  }

  static HlsRendition? audioFor(StreamVariant v, List<HlsRendition> renditions) {
    if (v.audioGroup.isEmpty) return null;
    final group = renditions.where((r) => r.type == 'AUDIO' && r.group == v.audioGroup).toList();
    if (group.isEmpty) return null;
    return group.firstWhere((r) => r.isDefault, orElse: () => group.first);
  }

  static ({StreamTrack? video, StreamTrack? audio}) dash(
    String text,
    Uri mpdUrl, {
    int maxHeight = 0,
    bool audioOnly = false,
  }) {
    final mpd = XmlDocument.parse(text).rootElement;
    if (mpd.getAttribute('type') == 'dynamic') throw live;
    if (mpd.descendants.whereType<XmlElement>().any((e) => e.name.local == 'ContentProtection')) throw drm;
    final periods = _kids(mpd, 'Period').toList();
    if (periods.isEmpty) throw const StreamPlanException("Can't read this stream.");
    final total = _seconds(mpd.getAttribute('mediaPresentationDuration'));
    final mpdBase = _base(mpd, mpdUrl);

    final videoRuns = <StreamRun>[];
    final audioRuns = <StreamRun>[];
    var webm = false;
    var start = 0.0;
    for (var i = 0; i < periods.length; i++) {
      final period = periods[i];
      start = _seconds(period.getAttribute('start')) ?? start;
      final nextStart = i + 1 < periods.length ? _seconds(periods[i + 1].getAttribute('start')) : null;
      final seconds = _seconds(period.getAttribute('duration')) ??
          (nextStart != null ? nextStart - start : (total != null ? total - start : 0.0));
      final base = _base(period, mpdBase);

      final videos = <(XmlElement, XmlElement)>[];
      final audios = <(XmlElement, XmlElement)>[];
      for (final set in _kids(period, 'AdaptationSet')) {
        for (final rep in _kids(set, 'Representation')) {
          final mime = rep.getAttribute('mimeType') ?? set.getAttribute('mimeType') ?? '';
          final type = set.getAttribute('contentType') ?? (mime.isEmpty ? _typeOfCodec(_codecs(set, rep)) : mime.split('/').first);
          if (mime.endsWith('/webm')) {
            if (type == 'video' || type == 'audio') webm = true;
            continue;
          }
          if (type == 'video') videos.add((set, rep));
          if (type == 'audio') audios.add((set, rep));
        }
      }
      int attr(XmlElement e, String name) => int.tryParse(e.getAttribute(name) ?? '') ?? 0;
      // Any codec is muxed as is; at equal height prefer what plays on
      // iPhone (H.264, then HEVC, AV1, VP9).
      videos.sort((a, b) {
        final h = attr(b.$2, 'height').compareTo(attr(a.$2, 'height'));
        if (h != 0) return h;
        final c = _videoRank(_codecs(a.$1, a.$2)).compareTo(_videoRank(_codecs(b.$1, b.$2)));
        return c != 0 ? c : attr(b.$2, 'bandwidth').compareTo(attr(a.$2, 'bandwidth'));
      });
      audios.sort((a, b) {
        final c = _audioRank(_codecs(a.$1, a.$2)).compareTo(_audioRank(_codecs(b.$1, b.$2)));
        return c != 0 ? c : attr(b.$2, 'bandwidth').compareTo(attr(a.$2, 'bandwidth'));
      });
      if (!audioOnly && videos.isNotEmpty) {
        final best = videos.first;
        final capped = maxHeight <= 0
            ? best
            : videos.firstWhere((v) => attr(v.$2, 'height') <= maxHeight, orElse: () => videos.last);
        videoRuns.add(_dashRun(period, capped.$1, capped.$2, base, seconds));
      }
      if (audios.isNotEmpty) audioRuns.add(_dashRun(period, audios.first.$1, audios.first.$2, base, seconds));
      start += seconds;
    }
    if (videoRuns.isEmpty && audioRuns.isEmpty) {
      throw webm ? webmOnly : const StreamPlanException('No downloadable video or audio in this stream.');
    }
    if (!audioOnly && videoRuns.isEmpty && webm) throw webmOnly;
    return (
      video: videoRuns.isEmpty ? null : StreamTrack(videoRuns),
      audio: audioRuns.isEmpty ? null : StreamTrack(audioRuns),
    );
  }

  static String _codecs(XmlElement set, XmlElement rep) =>
      (rep.getAttribute('codecs') ?? set.getAttribute('codecs') ?? '').toLowerCase();

  static String _typeOfCodec(String c) =>
      RegExp(r'^(avc|hvc|hev|av01|vp0|dvh)').hasMatch(c) ? 'video' : (c.isEmpty ? '' : 'audio');

  static int _videoRank(String c) => c.startsWith('avc')
      ? 0
      : c.startsWith('hvc') || c.startsWith('hev')
      ? 1
      : c.startsWith('av01')
      ? 2
      : c.startsWith('vp09')
      ? 3
      : 4;

  static int _audioRank(String c) => c.startsWith('mp4a')
      ? 0
      : c.startsWith('ec-3') || c.startsWith('ac-3')
      ? 1
      : c.startsWith('opus')
      ? 2
      : 3;

  static double? _seconds(String? iso) {
    final d = iso == null ? null : MediaManifest.isoDuration(iso);
    return d == null ? null : d.inMicroseconds / 1e6;
  }

  static StreamRun _dashRun(XmlElement period, XmlElement set, XmlElement rep, Uri base, double seconds) {
    final url = _base(rep, _base(set, base));
    final templates = [for (final e in [period, set, rep]) ..._kids(e, 'SegmentTemplate')];
    if (templates.isNotEmpty) {
      String? attr(String name) {
        for (final t in templates.reversed) {
          final v = t.getAttribute(name);
          if (v != null) return v;
        }
        return null;
      }

      final id = rep.getAttribute('id') ?? '';
      final bandwidth = rep.getAttribute('bandwidth') ?? '';
      String fill(String t, {int number = 0, int time = 0}) => t
          .replaceAllMapped(_template, (m) {
            final value = switch (m[1]) {
              'RepresentationID' => id,
              'Bandwidth' => bandwidth,
              'Number' => '$number',
              _ => '$time',
            };
            final width = int.tryParse(m[2] ?? '');
            return width == null ? value : value.padLeft(width, '0');
          })
          .replaceAll(r'$$', r'$');

      final timescale = int.tryParse(attr('timescale') ?? '') ?? 1;
      final start = int.tryParse(attr('startNumber') ?? '') ?? 1;
      final media = attr('media') ?? '';
      final initTemplate = attr('initialization');
      final timeline = templates.reversed
          .map((t) => _kids(t, 'SegmentTimeline').firstOrNull)
          .whereType<XmlElement>()
          .firstOrNull;
      final segments = <SegmentRef>[];
      if (timeline != null) {
        final offset = int.tryParse(attr('presentationTimeOffset') ?? '') ?? 0;
        final end = offset + (seconds * timescale).round();
        var t = 0;
        var n = start;
        for (final s in _kids(timeline, 'S')) {
          t = int.tryParse(s.getAttribute('t') ?? '') ?? t;
          final d = int.tryParse(s.getAttribute('d') ?? '') ?? 0;
          if (d <= 0) continue;
          var r = int.tryParse(s.getAttribute('r') ?? '') ?? 0;
          if (r < 0) r = end > t ? ((end - t) / d).ceil() - 1 : 0;
          for (var i = 0; i <= r; i++) {
            segments.add(SegmentRef(url.resolve(fill(media, number: n, time: t)).toString()));
            t += d;
            n++;
          }
        }
      } else {
        final d = int.tryParse(attr('duration') ?? '') ?? 0;
        if (d <= 0 || seconds <= 0) throw const StreamPlanException("Can't read this stream's pieces.");
        final count = (seconds * timescale / d).ceil();
        for (var i = 0; i < count; i++) {
          segments.add(SegmentRef(url.resolve(fill(media, number: start + i)).toString()));
        }
      }
      return StreamRun(
        segments: segments,
        init: initTemplate == null ? null : SegmentRef(url.resolve(fill(initTemplate)).toString()),
      );
    }

    final list = [rep, set].map((e) => _kids(e, 'SegmentList').firstOrNull).whereType<XmlElement>().firstOrNull;
    if (list != null) {
      final init = _kids(list, 'Initialization').firstOrNull;
      return StreamRun(
        init: init == null ? null : _ref(url, init.getAttribute('sourceURL'), init.getAttribute('range')),
        segments: [
          for (final s in _kids(list, 'SegmentURL')) _ref(url, s.getAttribute('media'), s.getAttribute('mediaRange')),
        ],
      );
    }
    // SegmentBase (with its sidx) or a bare BaseURL: one complete MP4 file,
    // fetched whole; the muxer reads its fragments or sample tables.
    return StreamRun(segments: [SegmentRef(url.toString())]);
  }

  static Iterable<XmlElement> _kids(XmlElement e, String local) =>
      e.childElements.where((c) => c.name.local == local);

  static Uri _base(XmlElement e, Uri parent) {
    final b = _kids(e, 'BaseURL').firstOrNull?.innerText.trim();
    return b == null || b.isEmpty ? parent : parent.resolve(b);
  }

  static SegmentRef _ref(Uri base, String? media, String? range) {
    final url = media == null || media.isEmpty ? base.toString() : base.resolve(media).toString();
    final m = _range.firstMatch(range ?? '');
    if (m == null) return SegmentRef(url);
    final from = int.parse(m[1]!);
    return SegmentRef(url, offset: from, length: int.parse(m[2]!) - from + 1);
  }

  static (int, int?)? _byteRange(String? s) {
    if (s == null) return null;
    final parts = s.split('@');
    final length = int.tryParse(parts.first.trim());
    if (length == null) return null;
    return (length, parts.length > 1 ? int.tryParse(parts[1].trim()) : null);
  }

  static Uint8List? _hex(String? s) {
    if (s == null) return null;
    final h = s.toLowerCase().replaceFirst('0x', '').padLeft(32, '0');
    if (h.length != 32) return null;
    final bytes = Uint8List(16);
    for (var i = 0; i < 16; i++) {
      final b = int.tryParse(h.substring(i * 2, i * 2 + 2), radix: 16);
      if (b == null) return null;
      bytes[i] = b;
    }
    return bytes;
  }

  static Uint8List _sequenceIv(int sequence) {
    final iv = Uint8List(16);
    var n = sequence;
    for (var i = 15; i >= 0 && n > 0; i--) {
      iv[i] = n & 0xff;
      n >>= 8;
    }
    return iv;
  }
}
