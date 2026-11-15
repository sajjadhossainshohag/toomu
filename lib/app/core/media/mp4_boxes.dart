import 'dart:typed_data';

const syncSampleFlags = 0x02000000;
const otherSampleFlags = 0x01010000;

bool isSyncFlags(int flags) => flags & 0x00010000 == 0;

class MediaTrack {
  MediaTrack({
    required this.handler,
    required this.timescale,
    required this.entries,
    this.width = 0,
    this.height = 0,
  });

  final String handler;
  final int timescale;
  final List<Uint8List> entries; // raw stsd children: any codec passes through undecoded
  final int width;
  final int height;

  final List<String> files = [];
  final List<int> file = [];
  final List<int> offset = [];
  final List<int> size = [];
  final List<int> dts = [];
  final List<int> duration = [];
  final List<int> cto = [];
  final List<int> flags = [];
  final List<int> entry = [];

  bool get isVideo => handler == 'vide';
  int get length => size.length;

  void add({
    required int fileIndex,
    required int offset,
    required int size,
    required int dts,
    required int duration,
    int cto = 0,
    int flags = syncSampleFlags,
    int entry = 0,
  }) {
    file.add(fileIndex);
    this.offset.add(offset);
    this.size.add(size);
    this.dts.add(dts);
    this.duration.add(duration);
    this.cto.add(cto);
    this.flags.add(flags);
    this.entry.add(entry);
  }
}

class BoxWriter {
  final BytesBuilder _b = BytesBuilder(copy: false);

  int get length => _b.length;

  void u8(int v) => _b.addByte(v & 0xff);

  void u16(int v) {
    u8(v >> 8);
    u8(v);
  }

  void u24(int v) {
    u8(v >> 16);
    u16(v);
  }

  void u32(int v) {
    u16(v >> 16);
    u16(v);
  }

  void u64(int v) {
    u32(v >> 32);
    u32(v);
  }

  void zeros(int n) => _b.add(Uint8List(n));

  void fourcc(String s) => _b.add(s.codeUnits);

  void bytes(List<int> b) => _b.add(b);

  Uint8List take() => _b.takeBytes();
}

Uint8List mp4Box(String type, List<List<int>> parts) {
  var size = 8;
  for (final p in parts) {
    size += p.length;
  }
  final w = BoxWriter()
    ..u32(size)
    ..fourcc(type);
  for (final p in parts) {
    w.bytes(p);
  }
  return w.take();
}

Uint8List mp4FullBox(String type, int version, int flags, List<List<int>> parts) =>
    mp4Box(type, [
      [version, (flags >> 16) & 0xff, (flags >> 8) & 0xff, flags & 0xff],
      ...parts,
    ]);

class BoxView {
  BoxView(this.type, this.data, this.start, this.end);

  final String type;
  final Uint8List data;

  // Payload range in [data] (after the size/type header).
  final int start;
  final int end;

  int get version => data[start];
  int get flags => (data[start + 1] << 16) | (data[start + 2] << 8) | data[start + 3];

  Iterable<BoxView> children([int skip = 0]) => boxesIn(data, start + skip, end);

  BoxView? child(String type, [int skip = 0]) {
    for (final b in children(skip)) {
      if (b.type == type) return b;
    }
    return null;
  }

  Uint8List get raw => Uint8List.sublistView(data, start - 8, end);
}

Iterable<BoxView> boxesIn(Uint8List data, int from, int to) sync* {
  var p = from;
  while (p + 8 <= to) {
    var size = readU32(data, p);
    final type = String.fromCharCodes(data, p + 4, p + 8);
    var header = 8;
    if (size == 1) {
      if (p + 16 > to) return;
      size = readU64(data, p + 8);
      header = 16;
    } else if (size == 0) {
      size = to - p;
    }
    if (size < header || p + size > to) return;
    yield BoxView(type, data, p + header, p + size);
    p += size;
  }
}

int readU16(Uint8List d, int p) => (d[p] << 8) | d[p + 1];
int readU24(Uint8List d, int p) => (d[p] << 16) | (d[p + 1] << 8) | d[p + 2];
int readU32(Uint8List d, int p) => (d[p] << 24) | (d[p + 1] << 16) | (d[p + 2] << 8) | d[p + 3];
int readI32(Uint8List d, int p) => readU32(d, p).toSigned(32);
int readU64(Uint8List d, int p) => (readU32(d, p) << 32) | readU32(d, p + 4);
