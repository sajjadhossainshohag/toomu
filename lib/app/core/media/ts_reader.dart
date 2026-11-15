import 'dart:io';
import 'dart:typed_data';

import 'mp4_boxes.dart';

typedef TsTracks = ({MediaTrack? video, MediaTrack? audio});

abstract class TsReader {
  static const _aacRates = [96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350];

  static TsTracks read(String path, String samplesPath) {
    final demux = _TsDemux('$samplesPath.video', '$samplesPath.audio');
    final raf = File(path).openSync();
    try {
      var carry = Uint8List(0);
      while (true) {
        final chunk = raf.readSync(188 * 4096);
        if (chunk.isEmpty) break;
        final data = carry.isEmpty
            ? chunk
            : (BytesBuilder(copy: false)
                  ..add(carry)
                  ..add(chunk))
                .takeBytes();
        var p = 0;
        while (p + 188 <= data.length) {
          if (data[p] != 0x47) {
            p++;
            continue;
          }
          demux.packet(data, p);
          p += 188;
        }
        carry = Uint8List.fromList(Uint8List.sublistView(data, p));
      }
      return demux.finish();
    } finally {
      raf.closeSync();
      demux.close();
    }
  }

  static MediaTrack? readAac(String path) {
    // HLS packed audio: ADTS frames, each segment starting with an ID3 tag
    // that carries the MPEG-TS timestamp, so it stays in sync with video.
    final data = File(path).readAsBytesSync();
    final adts = _Adts();
    var p = 0;
    while (p < data.length) {
      if (p + 10 <= data.length && data[p] == 0x49 && data[p + 1] == 0x44 && data[p + 2] == 0x33) {
        final size = (data[p + 6] << 21) | (data[p + 7] << 14) | (data[p + 8] << 7) | data[p + 9];
        final total = 10 + size + (data[p + 5] & 0x10 != 0 ? 10 : 0);
        adts.startPts ??= _id3Timestamp(data, p, p + total);
        p += total;
        continue;
      }
      final used = adts.frame(data, p, (offset, size) => offset);
      if (used == 0) {
        p++;
      } else if (used < 0) {
        break;
      } else {
        p += used;
      }
    }
    return adts.track(path);
  }

  static int? _id3Timestamp(Uint8List d, int from, int to) {
    const owner = 'com.apple.streaming.transportStreamTimestamp';
    var p = from + 10;
    while (p + 10 <= to && p + 10 <= d.length) {
      final id = String.fromCharCodes(d, p, p + 4);
      final size = readU32(d, p + 4);
      final body = p + 10;
      if (size <= 0 || body + size > d.length) return null;
      if (id == 'PRIV' && size >= owner.length + 9 && String.fromCharCodes(d, body, body + owner.length) == owner) {
        return readU64(d, body + owner.length + 1) & 0x1FFFFFFFF;
      }
      p = body + size;
    }
    return null;
  }

  static Uint8List aacEntry(int objectType, int rateIndex, int channels, int rate) {
    final asc = [(objectType << 3) | (rateIndex >> 1), ((rateIndex & 1) << 7) | (channels << 3)];
    final dsi = [0x05, asc.length, ...asc];
    final dcd = [0x04, 13 + dsi.length, 0x40, 0x15, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, ...dsi];
    const sl = [0x06, 1, 0x02];
    final es = [0x03, 3 + dcd.length + sl.length, 0, 0, 0, ...dcd, ...sl];
    final e = BoxWriter()
      ..zeros(6)
      ..u16(1)
      ..zeros(8)
      ..u16(channels == 0 ? 2 : channels)
      ..u16(16)
      ..u32(0)
      ..u32((rate & 0xffff) << 16);
    return mp4Box('mp4a', [
      e.take(),
      mp4FullBox('esds', 0, 0, [es]),
    ]);
  }
}

class _Adts {
  int? startPts; // 90 kHz
  int? rateIndex;
  int objectType = 2;
  int channels = 2;
  int frames = 0;
  final offsets = <int>[];
  final sizes = <int>[];
  final dts = <int>[];
  final durations = <int>[];

  int get rate => TsReader._aacRates[rateIndex ?? 4];

  int frame(Uint8List d, int p, int Function(int offset, int size) store) {
    // Returns 0 when no frame starts at [p], -1 when it's incomplete, else
    // its length; [store] says where the payload ended up.
    if (p + 7 > d.length) return -1;
    if (d[p] != 0xFF || d[p + 1] & 0xF6 != 0xF0) return 0;
    final header = d[p + 1] & 1 == 1 ? 7 : 9;
    final index = (d[p + 2] >> 2) & 0xF;
    final length = ((d[p + 3] & 3) << 11) | (d[p + 4] << 3) | (d[p + 5] >> 5);
    if (index >= 13 || length <= header) return 0;
    if (p + length > d.length) return -1;
    if (rateIndex == null) {
      rateIndex = index;
      objectType = (d[p + 2] >> 6) + 1;
      channels = ((d[p + 2] & 1) << 2) | (d[p + 3] >> 6);
    }
    final blocks = (d[p + 6] & 3) + 1;
    final start = ((startPts ?? 0) * rate / 90000).round();
    offsets.add(store(p + header, length - header));
    sizes.add(length - header);
    dts.add(start + frames * 1024);
    durations.add(1024 * blocks);
    frames += blocks;
    return length;
  }

  MediaTrack? track(String file) {
    if (sizes.isEmpty || rateIndex == null) return null;
    final t = MediaTrack(
      handler: 'soun',
      timescale: rate,
      entries: [TsReader.aacEntry(objectType, rateIndex!, channels, rate)],
    )..files.add(file);
    for (var i = 0; i < sizes.length; i++) {
      t.add(fileIndex: 0, offset: offsets[i], size: sizes[i], dts: dts[i], duration: durations[i]);
    }
    return t;
  }
}

class _TsDemux {
  _TsDemux(this.videoPath, this.audioPath)
    : _videoOut = File(videoPath).openSync(mode: FileMode.write),
      _audioOut = File(audioPath).openSync(mode: FileMode.write);

  // Separate files: a picture split over PES packets is appended to the
  // video file and must stay contiguous.
  final String videoPath;
  final String audioPath;
  final RandomAccessFile _videoOut;
  final RandomAccessFile _audioOut;
  int _videoWritten = 0;
  int _audioWritten = 0;

  void close() {
    _videoOut.closeSync();
    _audioOut.closeSync();
  }

  int _pmtPid = -1;
  int _videoPid = -1;
  int _audioPid = -1;
  final _videoPes = BytesBuilder();
  final _audioPes = BytesBuilder();

  Uint8List? _sps;
  Uint8List? _pps;
  bool _started = false;
  List<Uint8List>? _au;
  int _auPts = 0;
  int _auDts = 0;
  final _vOffset = <int>[];
  final _vSize = <int>[];
  final _vDts = <int>[];
  final _vPts = <int>[];
  final _vSync = <bool>[];

  final _adts = _Adts();
  final _audioCarry = BytesBuilder(copy: false);

  final _wrap = <bool, (int, int)>{}; // stream -> (last value, offset)

  void packet(Uint8List d, int p) {
    final start = d[p + 1] & 0x40 != 0;
    final pid = ((d[p + 1] & 0x1f) << 8) | d[p + 2];
    final control = (d[p + 3] >> 4) & 3;
    var from = p + 4;
    if (control == 2 || control == 3) from += 1 + d[p + 4];
    if (control == 0 || control == 2 || from >= p + 188) return;
    final payload = Uint8List.sublistView(d, from, p + 188);
    if (pid == 0) {
      if (start) _pat(payload);
    } else if (pid == _pmtPid) {
      if (start) _pmt(payload);
    } else if (pid == _videoPid) {
      _pes(_videoPes, payload, start, video: true);
    } else if (pid == _audioPid) {
      _pes(_audioPes, payload, start, video: false);
    }
  }

  void _pat(Uint8List b) {
    final s = 1 + b[0];
    if (s + 8 > b.length) return;
    final end = (s + 3 + (((b[s + 1] & 0x0f) << 8) | b[s + 2]) - 4).clamp(0, b.length);
    for (var q = s + 8; q + 4 <= end; q += 4) {
      if (readU16(b, q) != 0) {
        _pmtPid = ((b[q + 2] & 0x1f) << 8) | b[q + 3];
        return;
      }
    }
  }

  void _pmt(Uint8List b) {
    final s = 1 + b[0];
    if (s + 12 > b.length) return;
    final end = (s + 3 + (((b[s + 1] & 0x0f) << 8) | b[s + 2]) - 4).clamp(0, b.length);
    var q = s + 12 + (((b[s + 10] & 0x0f) << 8) | b[s + 11]);
    while (q + 5 <= end) {
      final type = b[q];
      final pid = ((b[q + 1] & 0x1f) << 8) | b[q + 2];
      if (_videoPid < 0 && (type == 0x1B || type == 0x24)) {
        if (type == 0x24) throw const FormatException("HEVC in MPEG-TS isn't supported yet");
        _videoPid = pid;
      } else if (_audioPid < 0 && const {0x0F, 0x03, 0x04, 0x11, 0x81, 0x87}.contains(type)) {
        if (type != 0x0F) throw const FormatException("This MPEG-TS audio codec isn't supported yet (only AAC)");
        _audioPid = pid;
      }
      q += 5 + (((b[q + 3] & 0x0f) << 8) | b[q + 4]);
    }
  }

  void _pes(BytesBuilder buf, Uint8List payload, bool start, {required bool video}) {
    if (start) {
      if (buf.isNotEmpty) _flush(buf.takeBytes(), video);
    } else if (buf.isEmpty) {
      return;
    }
    buf.add(payload);
  }

  void _flush(Uint8List pes, bool video) {
    if (pes.length < 9 || pes[0] != 0 || pes[1] != 0 || pes[2] != 1) return;
    final flags = pes[7] >> 6;
    final bodyAt = 9 + pes[8];
    if (bodyAt > pes.length) return;
    final pts = flags & 2 != 0 ? _unwrap(_timestamp(pes, 9), video) : null;
    final dts = flags == 3 ? _unwrap(_timestamp(pes, 14), video) : pts;
    final body = Uint8List.sublistView(pes, bodyAt);
    if (video) {
      _video(body, pts, dts);
    } else {
      _audio(body, pts);
    }
  }

  static int _timestamp(Uint8List b, int p) =>
      (((b[p] >> 1) & 7) << 30) | (b[p + 1] << 22) | ((b[p + 2] >> 1) << 15) | (b[p + 3] << 7) | (b[p + 4] >> 1);

  int _unwrap(int v, bool video) {
    // Timestamps are 33-bit and wrap about every 26.5 hours.
    final (last, offset) = _wrap[video] ?? (v, 0);
    var o = offset;
    if (v + o < last - (1 << 32)) o += 1 << 33;
    if (v + o > last + (1 << 32)) o -= 1 << 33;
    _wrap[video] = (v + o, o);
    return v + o;
  }


  void _video(Uint8List body, int? pts, int? dts) {
    // PES packets need not end on a picture boundary (Apple's segmenter
    // starts each one with the tail of the previous slice): bytes before
    // the first start code finish the last NAL unit, and a timestamped PES
    // starts the next picture.
    final (lead, nals) = _split(body);
    final au = _au;
    if (lead.isNotEmpty && au != null && au.isNotEmpty) {
      au[au.length - 1] = (BytesBuilder(copy: false)
            ..add(au.last)
            ..add(lead))
          .takeBytes();
    }
    if (pts != null && dts != null) {
      _finishPicture();
      _au = [...nals];
      _auPts = pts;
      _auDts = dts;
    } else {
      au?.addAll(nals);
    }
  }

  void _finishPicture() {
    final au = _au;
    _au = null;
    if (au == null) return;
    final sample = BytesBuilder(copy: false);
    var idr = false;
    for (var n in au) {
      var end = n.length;
      while (end > 0 && n[end - 1] == 0) {
        end--;
      }
      if (end == 0) continue;
      n = Uint8List.sublistView(n, 0, end);
      final type = n[0] & 0x1f;
      if (type == 7) {
        _sps ??= Uint8List.fromList(n);
      } else if (type == 8) {
        _pps ??= Uint8List.fromList(n);
      } else if (type != 9) {
        if (type == 5) idr = true;
        sample
          ..add([(n.length >> 24) & 0xff, (n.length >> 16) & 0xff, (n.length >> 8) & 0xff, n.length & 0xff])
          ..add(n);
      }
    }
    if (sample.isEmpty) return;
    if (!_started) {
      if (!idr || _sps == null || _pps == null) return; // decoding starts at a keyframe
      _started = true;
    }
    final bytes = sample.takeBytes();
    _vOffset.add(_videoWritten);
    _vSize.add(bytes.length);
    _vDts.add(_auDts);
    _vPts.add(_auPts);
    _vSync.add(idr);
    _videoOut.writeFromSync(bytes);
    _videoWritten += bytes.length;
  }

  void _audio(Uint8List body, int? pts) {
    if (pts != null) _adts.startPts ??= pts;
    _audioCarry.add(body);
    final d = _audioCarry.takeBytes();
    var p = 0;
    while (p < d.length) {
      final used = _adts.frame(d, p, (offset, size) {
        final at = _audioWritten;
        _audioOut.writeFromSync(Uint8List.sublistView(d, offset, offset + size));
        _audioWritten += size;
        return at;
      });
      if (used < 0) break;
      p += used == 0 ? 1 : used;
    }
    if (p < d.length) _audioCarry.add(Uint8List.fromList(Uint8List.sublistView(d, p)));
  }

  static (Uint8List, List<Uint8List>) _split(Uint8List b) {
    // Bytes before the first start code, then each NAL unit (the last one
    // may continue in the next PES; trailing zeros are trimmed later).
    final starts = <int>[];
    for (var i = 0; i + 2 < b.length; i++) {
      if (b[i + 2] > 1) {
        i += 2;
      } else if (b[i] == 0 && b[i + 1] == 0 && b[i + 2] == 1) {
        starts.add(i + 3);
        i += 2;
      }
    }
    if (starts.isEmpty) return (b, const <Uint8List>[]);
    return (
      Uint8List.sublistView(b, 0, starts.first - 3),
      [
        for (var k = 0; k < starts.length; k++)
          Uint8List.fromList(
            Uint8List.sublistView(b, starts[k], k + 1 < starts.length ? starts[k + 1] - 3 : b.length),
          ),
      ],
    );
  }

  TsTracks finish() {
    if (_videoPes.isNotEmpty) _flush(_videoPes.takeBytes(), true);
    _finishPicture();
    if (_audioPes.isNotEmpty) _flush(_audioPes.takeBytes(), false);
    return (video: _videoTrack(), audio: _adts.track(audioPath));
  }

  MediaTrack? _videoTrack() {
    final sps = _sps, pps = _pps;
    if (_vSize.isEmpty || sps == null || pps == null) return null;
    final info = Sps.parse(sps);
    final t = MediaTrack(
      handler: 'vide',
      timescale: 90000,
      entries: [info.avc1(sps, pps)],
      width: info.width,
      height: info.height,
    )..files.add(videoPath);
    for (var i = 0; i < _vSize.length; i++) {
      final duration = i + 1 < _vDts.length
          ? _vDts[i + 1] - _vDts[i]
          : (i > 0 ? _vDts[i] - _vDts[i - 1] : 3000);
      t.add(
        fileIndex: 0,
        offset: _vOffset[i],
        size: _vSize[i],
        dts: _vDts[i],
        duration: duration > 0 ? duration : 1,
        cto: _vPts[i] - _vDts[i] > 0 ? _vPts[i] - _vDts[i] : 0,
        flags: _vSync[i] ? syncSampleFlags : otherSampleFlags,
      );
    }
    return t;
  }
}

class Sps {
  Sps._(this.profile, this.chroma, this.depthLuma, this.depthChroma, this.width, this.height);

  final int profile;
  final int chroma;
  final int depthLuma;
  final int depthChroma;
  final int width;
  final int height;

  static const _highProfiles = {100, 110, 122, 244, 44, 83, 86, 118, 128, 138, 139, 134, 135};

  static Sps parse(Uint8List nal) {
    final r = _Bits(nal);
    r.bits(8);
    final profile = r.bits(8);
    r.bits(16);
    r.ue();
    var chroma = 1, depthL = 0, depthC = 0;
    if (_highProfiles.contains(profile)) {
      chroma = r.ue();
      if (chroma == 3) r.bit();
      depthL = r.ue();
      depthC = r.ue();
      r.bit();
      if (r.bit() == 1) {
        for (var i = 0; i < (chroma != 3 ? 8 : 12); i++) {
          if (r.bit() == 1) {
            var last = 8, next = 8;
            for (var j = 0; j < (i < 6 ? 16 : 64); j++) {
              if (next != 0) next = (last + r.se() + 256) % 256;
              last = next == 0 ? last : next;
            }
          }
        }
      }
    }
    r.ue();
    final pocType = r.ue();
    if (pocType == 0) {
      r.ue();
    } else if (pocType == 1) {
      r.bit();
      r.se();
      r.se();
      final n = r.ue();
      for (var i = 0; i < n; i++) {
        r.se();
      }
    }
    r.ue();
    r.bit();
    final widthMbs = r.ue() + 1;
    final heightMap = r.ue() + 1;
    final frameMbsOnly = r.bit();
    if (frameMbsOnly == 0) r.bit();
    r.bit();
    var left = 0, right = 0, top = 0, bottom = 0;
    if (r.bit() == 1) {
      left = r.ue();
      right = r.ue();
      top = r.ue();
      bottom = r.ue();
    }
    final cropX = chroma == 0 ? 1 : (chroma == 3 ? 1 : 2);
    final cropY = (chroma == 1 ? 2 : 1) * (2 - frameMbsOnly);
    return Sps._(
      profile,
      chroma,
      depthL,
      depthC,
      widthMbs * 16 - (left + right) * cropX,
      (2 - frameMbsOnly) * heightMap * 16 - (top + bottom) * cropY,
    );
  }

  Uint8List avc1(Uint8List sps, Uint8List pps) {
    final c = BoxWriter()
      ..u8(1)
      ..u8(sps[1])
      ..u8(sps[2])
      ..u8(sps[3])
      ..u8(0xFF)
      ..u8(0xE1)
      ..u16(sps.length)
      ..bytes(sps)
      ..u8(1)
      ..u16(pps.length)
      ..bytes(pps);
    if (const {100, 110, 122, 144}.contains(profile)) {
      c
        ..u8(0xFC | chroma)
        ..u8(0xF8 | depthLuma)
        ..u8(0xF8 | depthChroma)
        ..u8(0);
    }
    final e = BoxWriter()
      ..zeros(6)
      ..u16(1)
      ..zeros(16)
      ..u16(width)
      ..u16(height)
      ..u32(0x00480000)
      ..u32(0x00480000)
      ..u32(0)
      ..u16(1)
      ..zeros(32)
      ..u16(0x18)
      ..u16(0xFFFF);
    return mp4Box('avc1', [e.take(), mp4Box('avcC', [c.take()])]);
  }
}

class _Bits {
  _Bits(Uint8List nal) : _d = _rbsp(nal);

  final Uint8List _d;
  int _p = 0;

  int bit() {
    final byte = _p >> 3;
    if (byte >= _d.length) throw const FormatException('SPS ended early');
    final v = (_d[byte] >> (7 - (_p & 7))) & 1;
    _p++;
    return v;
  }

  int bits(int n) {
    var v = 0;
    for (var i = 0; i < n; i++) {
      v = (v << 1) | bit();
    }
    return v;
  }

  int ue() {
    var zeros = 0;
    while (bit() == 0) {
      if (++zeros > 31) throw const FormatException('Bad exp-Golomb code');
    }
    return (1 << zeros) - 1 + bits(zeros);
  }

  int se() {
    final k = ue();
    return k.isOdd ? (k + 1) ~/ 2 : -(k ~/ 2);
  }

  static Uint8List _rbsp(Uint8List n) {
    // Drops emulation-prevention bytes (00 00 03 -> 00 00).
    final out = BytesBuilder(copy: false);
    var zeros = 0;
    for (final b in n) {
      if (zeros >= 2 && b == 3) {
        zeros = 0;
        continue;
      }
      out.addByte(b);
      zeros = b == 0 ? zeros + 1 : 0;
    }
    return out.takeBytes();
  }
}
