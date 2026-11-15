import 'dart:io';
import 'dart:typed_data';

import 'mp4_boxes.dart';

abstract class Mp4Reader {
  static MediaTrack? read(String path, String handler) {
    final raf = File(path).openSync();
    try {
      final length = raf.lengthSync();
      Uint8List? moov;
      final moofs = <(int, Uint8List)>[];
      var p = 0;
      while (p + 8 <= length) {
        raf.setPositionSync(p);
        final h = raf.readSync(16);
        if (h.length < 8) break;
        var size = readU32(h, 0);
        final type = String.fromCharCodes(h, 4, 8);
        if (size == 1) {
          if (h.length < 16) break;
          size = readU64(h, 8);
        } else if (size == 0) {
          size = length - p;
        }
        if (size < 8 || p + size > length) break;
        if (type == 'moov' || type == 'moof') {
          raf.setPositionSync(p);
          final data = raf.readSync(size);
          if (type == 'moov') {
            moov = data;
          } else {
            moofs.add((p, data));
          }
        }
        p += size;
      }
      if (moov == null) throw const FormatException('No moov box: not an MP4 file');
      final root = boxesIn(moov, 0, moov.length).first;

      for (final trak in root.children().where((b) => b.type == 'trak')) {
        final mdia = trak.child('mdia');
        final hdlr = mdia?.child('hdlr');
        if (mdia == null || hdlr == null) continue;
        if (String.fromCharCodes(hdlr.data, hdlr.start + 8, hdlr.start + 12) != handler) continue;
        final tkhd = trak.child('tkhd')!;
        final trackId = readU32(tkhd.data, tkhd.start + (tkhd.version == 1 ? 20 : 12));
        final mdhd = mdia.child('mdhd')!;
        final timescale = readU32(mdhd.data, mdhd.start + (mdhd.version == 1 ? 20 : 12));
        final stbl = mdia.child('minf')?.child('stbl');
        final stsd = stbl?.child('stsd');
        if (stbl == null || stsd == null) continue;
        final track = MediaTrack(
          handler: handler,
          timescale: timescale,
          entries: [for (final e in stsd.children(8)) Uint8List.fromList(e.raw)],
          width: readU32(tkhd.data, tkhd.end - 8) >> 16,
          height: readU32(tkhd.data, tkhd.end - 4) >> 16,
        )..files.add(path);
        if (moofs.isEmpty) {
          _readTables(track, stbl);
        } else {
          _readFragments(track, trackId, root.child('mvex'), moofs);
        }
        return track;
      }
      return null;
    } finally {
      raf.closeSync();
    }
  }

  static void _readFragments(MediaTrack track, int trackId, BoxView? mvex, List<(int, Uint8List)> moofs) {
    var defSdi = 1, defDur = 0, defSize = 0, defFlags = 0;
    for (final trex in mvex?.children().where((b) => b.type == 'trex') ?? const <BoxView>[]) {
      final d = trex.data, s = trex.start + 4;
      if (readU32(d, s) != trackId) continue;
      defSdi = readU32(d, s + 4);
      defDur = readU32(d, s + 8);
      defSize = readU32(d, s + 12);
      defFlags = readU32(d, s + 16);
    }

    var nextDts = 0;
    for (final (moofStart, data) in moofs) {
      final moof = boxesIn(data, 0, data.length).first;
      var previousEnd = moofStart;
      var firstTraf = true;
      for (final traf in moof.children().where((b) => b.type == 'traf')) {
        final tfhd = traf.child('tfhd');
        if (tfhd == null) continue;
        final f = tfhd.flags;
        final d = tfhd.data;
        var q = tfhd.start + 4;
        final id = readU32(d, q);
        q += 4;
        int? baseOffset;
        if (f & 0x1 != 0) {
          baseOffset = readU64(d, q);
          q += 8;
        }
        var sdi = defSdi, dur = defDur, size = defSize, flags = defFlags;
        if (f & 0x2 != 0) {
          sdi = readU32(d, q);
          q += 4;
        }
        if (f & 0x8 != 0) {
          dur = readU32(d, q);
          q += 4;
        }
        if (f & 0x10 != 0) {
          size = readU32(d, q);
          q += 4;
        }
        if (f & 0x20 != 0) flags = readU32(d, q);
        // ISO 14496-12 8.8.7: explicit base, else the moof (default-base-is-moof
        // or first traf), else where the previous traf's data ended.
        final base = baseOffset ?? (f & 0x20000 != 0 || firstTraf ? moofStart : previousEnd);
        firstTraf = false;

        final ours = id == trackId;
        final tfdt = traf.child('tfdt');
        var time = ours && tfdt != null
            ? (tfdt.version == 1 ? readU64(tfdt.data, tfdt.start + 4) : readU32(tfdt.data, tfdt.start + 4))
            : nextDts;
        var pos = base;
        for (final trun in traf.children().where((b) => b.type == 'trun')) {
          final tf = trun.flags;
          final td = trun.data;
          var r = trun.start + 4;
          final count = readU32(td, r);
          r += 4;
          if (tf & 0x1 != 0) {
            pos = base + readI32(td, r);
            r += 4;
          }
          int? firstFlags;
          if (tf & 0x4 != 0) {
            firstFlags = readU32(td, r);
            r += 4;
          }
          for (var i = 0; i < count; i++) {
            var sDur = dur, sSize = size, sFlags = i == 0 && firstFlags != null ? firstFlags : flags, sCto = 0;
            if (tf & 0x100 != 0) {
              sDur = readU32(td, r);
              r += 4;
            }
            if (tf & 0x200 != 0) {
              sSize = readU32(td, r);
              r += 4;
            }
            if (tf & 0x400 != 0) {
              sFlags = readU32(td, r);
              r += 4;
            }
            if (tf & 0x800 != 0) {
              sCto = trun.version == 0 ? readU32(td, r) : readI32(td, r);
              r += 4;
            }
            if (ours) {
              track.add(
                fileIndex: 0,
                offset: pos,
                size: sSize,
                dts: time,
                duration: sDur,
                cto: sCto,
                flags: sFlags,
                entry: sdi - 1,
              );
            }
            time += sDur;
            pos += sSize;
          }
        }
        previousEnd = pos;
        if (ours) nextDts = time;
      }
    }
  }

  static void _readTables(MediaTrack track, BoxView stbl) {
    List<int> table(String type, int fields, {int skip = 4}) {
      final b = stbl.child(type);
      if (b == null) return const [];
      final count = readU32(b.data, b.start + skip);
      return [
        for (var i = 0; i < count * fields; i++) readU32(b.data, b.start + skip + 4 + i * 4),
      ];
    }

    final stsz = stbl.child('stsz') ?? stbl.child('stz2');
    if (stsz == null || stsz.type == 'stz2') throw const FormatException('Unsupported sample size table');
    final fixed = readU32(stsz.data, stsz.start + 4);
    final count = readU32(stsz.data, stsz.start + 8);
    final sizes = [
      for (var i = 0; i < count; i++) fixed != 0 ? fixed : readU32(stsz.data, stsz.start + 12 + i * 4),
    ];
    final stts = table('stts', 2);
    final ctts = table('ctts', 2);
    final cttsSigned = (stbl.child('ctts')?.version ?? 0) == 1;
    final stss = stbl.child('stss') == null ? null : table('stss', 1).toSet();
    final stsc = table('stsc', 3);
    final co64 = stbl.child('co64');
    final chunks = co64 == null
        ? table('stco', 1)
        : [
            for (var i = 0; i < readU32(co64.data, co64.start + 4); i++) readU64(co64.data, co64.start + 8 + i * 8),
          ];

    final offsets = <int>[];
    final entries = <int>[];
    var sample = 0;
    for (var c = 0; c < chunks.length && sample < count; c++) {
      var run = 0;
      while (run + 1 < stsc.length ~/ 3 && stsc[(run + 1) * 3] <= c + 1) {
        run++;
      }
      final perChunk = stsc[run * 3 + 1];
      final entry = stsc[run * 3 + 2] - 1;
      var pos = chunks[c];
      for (var i = 0; i < perChunk && sample < count; i++, sample++) {
        offsets.add(pos);
        entries.add(entry);
        pos += sizes[sample];
      }
    }

    var dts = 0, sttsRun = 0, sttsLeft = stts.isEmpty ? 0 : stts[0];
    var cttsRun = 0, cttsLeft = ctts.isEmpty ? 0 : ctts[0];
    for (var i = 0; i < offsets.length; i++) {
      while (sttsLeft == 0 && (sttsRun + 1) * 2 < stts.length) {
        sttsRun++;
        sttsLeft = stts[sttsRun * 2];
      }
      final delta = stts.isEmpty ? 0 : stts[sttsRun * 2 + 1];
      sttsLeft--;
      var cto = 0;
      if (ctts.isNotEmpty) {
        while (cttsLeft == 0 && (cttsRun + 1) * 2 < ctts.length) {
          cttsRun++;
          cttsLeft = ctts[cttsRun * 2];
        }
        cto = ctts[cttsRun * 2 + 1];
        if (cttsSigned) cto = cto.toSigned(32);
        cttsLeft--;
      }
      track.add(
        fileIndex: 0,
        offset: offsets[i],
        size: sizes[i],
        dts: dts,
        duration: delta,
        cto: cto,
        flags: stss == null || stss.contains(i + 1) ? syncSampleFlags : otherSampleFlags,
        entry: entries[i],
      );
      dts += delta;
    }
  }
}
