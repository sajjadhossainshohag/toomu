import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'mp4_boxes.dart';

class _OutTrack {
  _OutTrack(this.id, this.runs)
    : handler = runs.first.handler,
      timescale = runs.first.timescale,
      width = runs.map((r) => r.width).reduce(math.max),
      height = runs.map((r) => r.height).reduce(math.max);

  final int id;
  final List<MediaTrack> runs;
  final String handler;
  final int timescale;
  final int width;
  final int height;
  final List<Uint8List> entries = [];

  // Per output sample: where it comes from and its new timing.
  final List<int> run = [];
  final List<int> index = [];
  final List<int> dts = [];
  final List<int> duration = [];
  final List<int> cto = [];
  final List<int> entry = [];
  final Map<int, Uint8List> prefix = {};

  int get end => dts.isEmpty ? 0 : dts.last + duration.last;
}

class _Fragment {
  _Fragment(this.track, this.from, this.to);

  final _OutTrack track;
  final int from;
  final int to;

  double get start => track.dts[from] / track.timescale;
}

abstract class Mp4Writer {
  static const _fragmentSeconds = 2;

  static void write(String out, List<List<MediaTrack>> tracks) {
    // Each entry of [tracks] is one output track: its runs (pieces between
    // HLS discontinuities or DASH periods) play one after another.
    final valid = [
      for (final runs in tracks) runs.where((t) => t.length > 0).toList(),
    ].where((r) => r.isNotEmpty).toList();
    if (valid.isEmpty) throw const FormatException('Nothing to write: no samples');
    final numbered = [for (var i = 0; i < valid.length; i++) _OutTrack(i + 1, valid[i])];
    _layout(numbered);

    final fragments = <_Fragment>[for (final t in numbered) ..._fragments(t)]
      ..sort((a, b) {
        final c = a.start.compareTo(b.start);
        return c != 0 ? c : a.track.id.compareTo(b.track.id);
      });
    final durationMs = numbered.map((t) => t.end * 1000 ~/ t.timescale).reduce(math.max);

    final sink = File(out).openSync(mode: FileMode.write);
    final sources = <String, RandomAccessFile>{};
    try {
      sink.writeFromSync(_ftyp());
      sink.writeFromSync(_moov(numbered, durationMs));
      var sequence = 1;
      for (final f in fragments) {
        _writeFragment(sink, f, sequence++, sources);
      }
    } finally {
      sink.closeSync();
      for (final s in sources.values) {
        s.closeSync();
      }
    }
  }

  static void _layout(List<_OutTrack> tracks) {
    double firstPts(MediaTrack r) {
      var best = r.dts.first + r.cto.first;
      for (var i = 1; i < math.min(r.length, 200); i++) {
        best = math.min(best, r.dts[i] + r.cto[i]);
      }
      return best / r.timescale;
    }

    // One clock for all tracks: the earliest presented sample of any track
    // is zero, shifted just enough that no decode time is negative (B-frames
    // decode before they're shown). Later runs continue where the last ended.
    final origin = tracks.map((t) => firstPts(t.runs.first)).reduce(math.min);
    final lead = tracks
        .map((t) => origin - t.runs.first.dts.first / t.runs.first.timescale)
        .fold<double>(0, math.max);
    for (final t in tracks) {
      for (var r = 0; r < t.runs.length; r++) {
        final run = t.runs[r];
        final scale = t.timescale / run.timescale;
        final mapped = <int>[];
        for (final e in run.entries) {
          var at = t.entries.indexWhere((x) => _same(x, e));
          if (at < 0) {
            t.entries.add(e);
            at = t.entries.length - 1;
          }
          mapped.add(at);
        }
        final start = r == 0
            ? ((run.dts.first / run.timescale - origin + lead) * t.timescale).round()
            : t.end;
        final first = run.dts.first;
        for (var i = 0; i < run.length; i++) {
          t.run.add(r);
          t.index.add(i);
          t.dts.add(start + ((run.dts[i] - first) * scale).round());
          t.cto.add((run.cto[i] * scale).round());
          t.entry.add(mapped[run.entry[i].clamp(0, mapped.length - 1)]);
          t.duration.add(0);
        }
        final from = t.dts.length - run.length;
        // A run with a new H.264/HEVC configuration also carries it in-band:
        // decoders that ignore sample-entry switches (FFmpeg, so mpv) need it.
        if (from > 0 && t.entry[from] != t.entry[from - 1]) {
          final sets = _parameterSets(t.entries[t.entry[from]]);
          if (sets != null) t.prefix[from] = sets;
        }
        for (var i = from; i < t.dts.length; i++) {
          t.duration[i] = i + 1 < t.dts.length
              ? t.dts[i + 1] - t.dts[i]
              : math.max(1, (run.duration[i - from] * scale).round());
        }
      }
    }
  }

  static List<_Fragment> _fragments(_OutTrack t) {
    final list = <_Fragment>[];
    final span = _fragmentSeconds * t.timescale;
    var from = 0;
    for (var i = 1; i < t.dts.length; i++) {
      final run = t.runs[t.run[i]];
      final sync = isSyncFlags(run.flags[t.index[i]]);
      final long = t.dts[i] - t.dts[from] >= span;
      // A fragment has one sample entry; video cuts only at keyframes.
      if (t.entry[i] != t.entry[from] || t.run[i] != t.run[from] || (long && (sync || t.handler != 'vide'))) {
        list.add(_Fragment(t, from, i));
        from = i;
      }
    }
    if (from < t.dts.length) list.add(_Fragment(t, from, t.dts.length));
    return list;
  }

  static void _writeFragment(RandomAccessFile sink, _Fragment f, int sequence, Map<String, RandomAccessFile> sources) {
    final t = f.track;
    final count = f.to - f.from;
    final trun = BoxWriter()
      ..u32(count)
      ..u32(0); // data offset, patched below
    var dataSize = 0;
    for (var i = f.from; i < f.to; i++) {
      final run = t.runs[t.run[i]];
      final s = t.index[i];
      final size = run.size[s] + (t.prefix[i]?.length ?? 0);
      trun
        ..u32(t.duration[i])
        ..u32(size)
        ..u32(run.flags[s])
        ..u32(t.cto[i] & 0xffffffff);
      dataSize += size;
    }
    final entry = t.entry[f.from];
    final tfhd = BoxWriter()..u32(t.id);
    if (entry > 0) tfhd.u32(entry + 1);
    final trunBytes = trun.take();
    final traf = mp4Box('traf', [
      mp4FullBox('tfhd', 0, 0x20000 | (entry > 0 ? 0x2 : 0), [tfhd.take()]),
      mp4FullBox('tfdt', 1, 0, [(BoxWriter()..u64(t.dts[f.from])).take()]),
      mp4FullBox('trun', 1, 0x1 | 0x100 | 0x200 | 0x400 | 0x800, [trunBytes]),
    ]);
    final moof = mp4Box('moof', [
      mp4FullBox('mfhd', 0, 0, [(BoxWriter()..u32(sequence)).take()]),
      traf,
    ]);
    // trun ends the moof; its data offset follows the sample count and points
    // past the mdat header.
    final trunAt = moof.length - trunBytes.length + 4;
    final dataOffset = moof.length + 8;
    moof
      ..[trunAt] = (dataOffset >> 24) & 0xff
      ..[trunAt + 1] = (dataOffset >> 16) & 0xff
      ..[trunAt + 2] = (dataOffset >> 8) & 0xff
      ..[trunAt + 3] = dataOffset & 0xff;
    sink.writeFromSync(moof);
    sink.writeFromSync((BoxWriter()
          ..u32(dataSize + 8)
          ..fourcc('mdat'))
        .take());

    // Copy sample bytes, reading neighbouring samples in one go.
    var i = f.from;
    while (i < f.to) {
      final prefix = t.prefix[i];
      if (prefix != null) sink.writeFromSync(prefix);
      final run = t.runs[t.run[i]];
      final s = t.index[i];
      final path = run.files[run.file[s]];
      final start = run.offset[s];
      var end = start + run.size[s];
      var j = i + 1;
      while (j < f.to && t.run[j] == t.run[i] && !t.prefix.containsKey(j)) {
        final s2 = t.index[j];
        if (run.files[run.file[s2]] != path || run.offset[s2] != end || end - start > 8 << 20) break;
        end += run.size[s2];
        j++;
      }
      final src = sources.putIfAbsent(path, () => File(path).openSync());
      src.setPositionSync(start);
      final bytes = src.readSync(end - start);
      if (bytes.length != end - start) throw FormatException('Sample data missing in $path');
      sink.writeFromSync(bytes);
      i = j;
    }
  }

  static Uint8List _ftyp() {
    final w = BoxWriter()
      ..fourcc('isom')
      ..u32(0x200)
      ..fourcc('isom')
      ..fourcc('iso6')
      ..fourcc('mp41');
    return mp4Box('ftyp', [w.take()]);
  }

  static const _matrix = [0x00010000, 0, 0, 0, 0x00010000, 0, 0, 0, 0x40000000];

  static Uint8List _moov(List<_OutTrack> tracks, int durationMs) {
    final mvhd = BoxWriter()
      ..u32(0)
      ..u32(0)
      ..u32(1000)
      ..u32(0)
      ..u32(0x00010000)
      ..u16(0x0100)
      ..zeros(10);
    for (final m in _matrix) {
      mvhd.u32(m);
    }
    mvhd
      ..zeros(24)
      ..u32(tracks.length + 1);
    return mp4Box('moov', [
      mp4FullBox('mvhd', 0, 0, [mvhd.take()]),
      for (final t in tracks) _trak(t),
      mp4Box('mvex', [
        mp4FullBox('mehd', 1, 0, [(BoxWriter()..u64(durationMs)).take()]),
        for (final t in tracks)
          mp4FullBox('trex', 0, 0, [
            (BoxWriter()
                  ..u32(t.id)
                  ..u32(1)
                  ..u32(0)
                  ..u32(0)
                  ..u32(0))
                .take(),
          ]),
      ]),
    ]);
  }

  static Uint8List _trak(_OutTrack t) {
    final video = t.handler == 'vide';
    final tkhd = BoxWriter()
      ..u32(0)
      ..u32(0)
      ..u32(t.id)
      ..u32(0)
      ..u32(0)
      ..zeros(8)
      ..u16(0)
      ..u16(0)
      ..u16(video ? 0 : 0x0100)
      ..u16(0);
    for (final m in _matrix) {
      tkhd.u32(m);
    }
    tkhd
      ..u32(t.width << 16)
      ..u32(t.height << 16);
    final mdhd = BoxWriter()
      ..u32(0)
      ..u32(0)
      ..u32(t.timescale)
      ..u32(0)
      ..u16(0x55c4) // "und"
      ..u16(0);
    final hdlr = BoxWriter()
      ..u32(0)
      ..fourcc(t.handler)
      ..zeros(12)
      ..bytes(video ? 'VideoHandler'.codeUnits : 'SoundHandler'.codeUnits)
      ..u8(0);
    final stsd = BoxWriter()..u32(t.entries.length);
    for (final e in t.entries) {
      stsd.bytes(e);
    }
    Uint8List empty(String type) => mp4FullBox(type, 0, 0, [Uint8List(4)]);
    return mp4Box('trak', [
      mp4FullBox('tkhd', 0, 0x3, [tkhd.take()]),
      mp4Box('mdia', [
        mp4FullBox('mdhd', 0, 0, [mdhd.take()]),
        mp4FullBox('hdlr', 0, 0, [hdlr.take()]),
        mp4Box('minf', [
          if (video) mp4FullBox('vmhd', 0, 1, [Uint8List(8)]) else mp4FullBox('smhd', 0, 0, [Uint8List(4)]),
          mp4Box('dinf', [
            mp4FullBox('dref', 0, 0, [
              (BoxWriter()..u32(1)).take(),
              mp4FullBox('url ', 0, 1, const []),
            ]),
          ]),
          mp4Box('stbl', [
            mp4FullBox('stsd', 0, 0, [stsd.take()]),
            empty('stts'),
            empty('stsc'),
            mp4FullBox('stsz', 0, 0, [Uint8List(8)]),
            empty('stco'),
          ]),
        ]),
      ]),
    ]);
  }

  static Uint8List? _parameterSets(Uint8List entry) {
    final type = String.fromCharCodes(entry, 4, 8);
    final avc = type.startsWith('avc');
    if (!avc && type != 'hvc1' && type != 'hev1') return null;
    // Child boxes follow the 78-byte VisualSampleEntry fields.
    final config = boxesIn(entry, 86, entry.length).where((b) => b.type == (avc ? 'avcC' : 'hvcC')).firstOrNull;
    if (config == null) return null;
    final d = config.data;
    final nals = <Uint8List>[];
    int lengthSize;
    var p = config.start;
    if (avc) {
      lengthSize = (d[p + 4] & 3) + 1;
      final sps = d[p + 5] & 0x1f;
      p += 6;
      for (var k = 0; k < sps; k++) {
        final n = readU16(d, p);
        nals.add(Uint8List.sublistView(d, p + 2, p + 2 + n));
        p += 2 + n;
      }
      final pps = d[p++];
      for (var k = 0; k < pps; k++) {
        final n = readU16(d, p);
        nals.add(Uint8List.sublistView(d, p + 2, p + 2 + n));
        p += 2 + n;
      }
    } else {
      lengthSize = (d[p + 21] & 3) + 1;
      final arrays = d[p + 22];
      p += 23;
      for (var a = 0; a < arrays; a++) {
        final count = readU16(d, p + 1);
        p += 3;
        for (var k = 0; k < count; k++) {
          final n = readU16(d, p);
          nals.add(Uint8List.sublistView(d, p + 2, p + 2 + n));
          p += 2 + n;
        }
      }
    }
    final w = BoxWriter();
    for (final n in nals) {
      for (var b = lengthSize - 1; b >= 0; b--) {
        w.u8(n.length >> (8 * b));
      }
      w.bytes(n);
    }
    return w.take();
  }

  static bool _same(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

