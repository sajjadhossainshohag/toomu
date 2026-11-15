import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:toomu/app/core/media/mp4_boxes.dart';
import 'package:toomu/app/core/media/mp4_reader.dart';
import 'package:toomu/app/core/media/mp4_writer.dart';
import 'package:toomu/app/core/media/ts_reader.dart';

Uint8List _hex(String h) =>
    Uint8List.fromList([for (var i = 0; i < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16)]);

final _sps240 = _hex('6764000dacd94141fb0110000003001000000303c0f1429960'); // x264, 320x240
final _sps360 = _hex('6764001eacd940a02ff970110000030001000003003c0f162d96'); // x264, 640x360
final _pps = _hex('68ef8fcb');

List<int> _ts(int pid, List<int> pes) {
  final out = <int>[];
  for (var p = 0; p < pes.length; p += 184) {
    final chunk = pes.sublist(p, p + 184 > pes.length ? pes.length : p + 184);
    final packet = <int>[0x47, (p == 0 ? 0x40 : 0) | (pid >> 8), pid & 0xff];
    if (chunk.length < 184) {
      final stuffing = 183 - chunk.length;
      packet
        ..add(0x30)
        ..add(stuffing);
      if (stuffing > 0) packet.addAll([0x00, ...List.filled(stuffing - 1, 0xff)]);
    } else {
      packet.add(0x10);
    }
    out.addAll(packet..addAll(chunk));
  }
  return out;
}

List<int> _timestamp(int prefix, int v) => [
  (prefix << 4) | ((v >> 29) & 0x0e) | 1,
  (v >> 22) & 0xff,
  ((v >> 14) & 0xfe) | 1,
  (v >> 7) & 0xff,
  ((v << 1) & 0xfe) | 1,
];

List<int> _pes(int streamId, int pts, List<int> body) => [
  0, 0, 1, streamId, 0, 0, 0x80, 0xc0, 10, //
  ..._timestamp(3, pts), ..._timestamp(1, pts),
  ...body,
];

List<int> _adts(int payloadLength, int fill) {
  final length = payloadLength + 7;
  return [
    0xff, 0xf1, 0x4c, 0x80 | ((length >> 11) & 3), (length >> 3) & 0xff, ((length & 7) << 5) | 0x1f, 0xfc, //
    ...List.filled(payloadLength, fill),
  ];
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('toomu_mux'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('SPS gives the picture size', () {
    expect([Sps.parse(_sps240).width, Sps.parse(_sps240).height], [320, 240]);
    expect([Sps.parse(_sps360).width, Sps.parse(_sps360).height], [640, 360]);
  });

  test('writer output reads back sample for sample; runs join on one clock', () {
    final data = File('${dir.path}/data')..writeAsBytesSync(List.generate(10000, (i) => i & 0xff));
    MediaTrack video(Uint8List sps, int firstDts) {
      final info = Sps.parse(sps);
      final t = MediaTrack(
        handler: 'vide',
        timescale: 90000,
        entries: [info.avc1(sps, _pps)],
        width: info.width,
        height: info.height,
      )..files.add(data.path);
      for (var i = 0; i < 4; i++) {
        t.add(
          fileIndex: 0,
          offset: i * 100,
          size: 100,
          dts: firstDts + i * 3000,
          duration: 3000,
          cto: 3000,
          flags: i == 0 ? syncSampleFlags : otherSampleFlags,
        );
      }
      return t;
    }

    // Audio on the same clock as the first video run (10.0333 s presented).
    final audio = MediaTrack(handler: 'soun', timescale: 48000, entries: [TsReader.aacEntry(2, 3, 2, 48000)])
      ..files.add(data.path);
    for (var i = 0; i < 6; i++) {
      audio.add(fileIndex: 0, offset: 5000 + i * 50, size: 50, dts: 481600 + i * 1024, duration: 1024);
    }
    final out = '${dir.path}/out.mp4';
    Mp4Writer.write(out, [
      [video(_sps240, 900000), video(_sps360, 5)],
      [audio],
    ]);

    final v = Mp4Reader.read(out, 'vide')!;
    final a = Mp4Reader.read(out, 'soun')!;
    expect(v.length, 8);
    expect(a.length, 6);
    expect(v.entries.length, 2);
    expect(v.entry, [0, 0, 0, 0, 1, 1, 1, 1]);
    expect(v.dts, [for (var i = 0; i < 8; i++) i * 3000]);
    expect(a.dts.first, 1600, reason: 'audio starts with the first video picture shown');
    expect([for (final f in v.flags) isSyncFlags(f)], [true, false, false, false, true, false, false, false]);

    // The second run's first sample also carries its SPS/PPS in-band.
    expect(v.size[4], 100 + 4 + _sps360.length + 4 + _pps.length);
    expect(v.size.where((s) => s == 100).length, 7);

    final raf = File(out).openSync();
    raf.setPositionSync(v.offset[1]);
    expect(raf.readSync(100), List.generate(100, (i) => (100 + i) & 0xff));
    raf.setPositionSync(a.offset[2]);
    expect(raf.readSync(50), List.generate(50, (i) => (5100 + i) & 0xff));
    raf.closeSync();
  });

  test('TS: pictures split across PES packets and AAC frames split across PES stay whole', () {
    const sc = [0, 0, 1];
    final idr = [0x65, ...List.filled(300, 0x11)];
    final slice = [0x41, ...List.filled(200, 0x22)];
    final pat = [0x00, 0x00, 0xb0, 13, 0x00, 0x01, 0xc1, 0x00, 0x00, 0x00, 0x01, 0xe1, 0x00, 0, 0, 0, 0];
    final pmt = [
      0x00, 0x02, 0xb0, 23, 0x00, 0x01, 0xc1, 0x00, 0x00, 0xe1, 0x01, 0xf0, 0x00, //
      0x1b, 0xe1, 0x01, 0xf0, 0x00, 0x0f, 0xe1, 0x02, 0xf0, 0x00, 0, 0, 0, 0,
    ];
    // Like Apple's segmenter: the second PES starts with the first picture's tail.
    final pes1 = _pes(0xe0, 900000, [...sc, 0x09, 0xf0, ...sc, ..._sps240, ...sc, ..._pps, ...sc, ...idr.sublist(0, 150)]);
    final pes2 = _pes(0xe0, 903000, [...idr.sublist(150), ...sc, 0x09, 0xf0, ...sc, ...slice]);
    final frames = [_adts(50, 0x31), _adts(50, 0x32), _adts(50, 0x33)];
    final audio1 = _pes(0xc0, 900000, [...frames[0], ...frames[1].sublist(0, 20)]);
    final audio2 = _pes(0xc0, 902160, [...frames[1].sublist(20), ...frames[2]]);

    final path = '${dir.path}/in.ts';
    File(path).writeAsBytesSync([
      ..._ts(0, pat),
      ..._ts(0x100, pmt),
      ..._ts(0x101, pes1),
      ..._ts(0x102, audio1),
      ..._ts(0x101, pes2),
      ..._ts(0x102, audio2),
    ]);
    final tracks = TsReader.read(path, '$path.samples');
    final v = tracks.video!;
    expect(v.size, [4 + idr.length, 4 + slice.length]);
    expect([v.width, v.height], [320, 240]);
    expect([for (final f in v.flags) isSyncFlags(f)], [true, false]);
    expect(v.dts, [900000, 903000]);

    final a = tracks.audio!;
    expect(a.timescale, 48000);
    expect(a.size, [50, 50, 50]);
    expect(a.dts, [480000, 481024, 482048]);
    final raf = File(a.files.first).openSync();
    raf.setPositionSync(a.offset[1]);
    expect(raf.readSync(50), List.filled(50, 0x32));
    raf.closeSync();
  });
}
