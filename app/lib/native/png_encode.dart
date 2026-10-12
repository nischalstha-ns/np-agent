import 'dart:typed_data';

/// REAL: Minimal PNG encoder in pure Dart (no dart:convert zlib needed).
///
/// Produces valid truecolor PNG bytes: 8-byte signature, IHDR, a single
/// IDAT chunk, IEND. Pixel data is wrapped as a zlib stream that uses
/// DEFLATE *stored* (uncompressed) blocks, so no compression tables are
/// required — every PNG decoder accepts stored blocks. Integrity fields
/// (Adler-32 for zlib, CRC-32/IEEE for PNG chunks) are computed inline.
///
/// Used by the mock desktop-control / OS-control channels to synthesize
/// screenshots without any native codec.
class PngEncode {
  /// REAL: Encode a solid-color truecolor PNG of [width]×[height].
  static Uint8List solidPng(int width, int height, int r, int g, int b) {
    final raw = BytesBuilder();
    for (var y = 0; y < height; y++) {
      raw.addByte(0); // filter type 0 (None)
      for (var x = 0; x < width; x++) {
        raw.add([r & 0xFF, g & 0xFF, b & 0xFF]);
      }
    }
    final deflated = _zlibStored(raw.takeBytes());

    final out = BytesBuilder();
    out.add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    final ihdr = BytesBuilder()
      ..add(_u32be(width))
      ..add(_u32be(height))
      ..add(const [8, 2, 0, 0, 0]); // 8-bit, truecolor
    _chunk(out, 'IHDR', ihdr.takeBytes());
    _chunk(out, 'IDAT', deflated);
    _chunk(out, 'IEND', const []);
    return out.takeBytes();
  }

  /// REAL: Wrap [data] in a zlib stream using DEFLATE stored blocks.
  static Uint8List _zlibStored(Uint8List data) {
    final out = BytesBuilder();
    out.add(const [0x78, 0x01]); // zlib header (deflate, FCHECK ok)
    var offset = 0;
    while (offset < data.length) {
      final end = (offset + 65535 < data.length)
          ? offset + 65535
          : data.length;
      final last = end == data.length;
      out.addByte(last ? 0x01 : 0x00); // BFINAL | BTYPE=00 (stored)
      final len = end - offset;
      out.addByte(len & 0xFF);
      out.addByte((len >> 8) & 0xFF);
      final nlen = (~len) & 0xFFFF;
      out.addByte(nlen & 0xFF);
      out.addByte((nlen >> 8) & 0xFF);
      out.add(data.sublist(offset, end));
      offset = end;
    }
    if (data.isEmpty) {
      // A single empty stored block so the stream is well-formed.
      out.add(const [0x01, 0x00, 0x00, 0xFF, 0xFF]);
    }
    final adler = _adler32(data);
    out.add([
      (adler >> 24) & 0xFF,
      (adler >> 16) & 0xFF,
      (adler >> 8) & 0xFF,
      adler & 0xFF,
    ]);
    return out.takeBytes();
  }

  /// REAL: Adler-32 checksum (used by the zlib wrapper).
  static int _adler32(Uint8List data) {
    var a = 1;
    var b = 0;
    for (final byte in data) {
      a = (a + byte) % 65521;
      b = (b + a) % 65521;
    }
    return ((b << 16) | a) & 0xFFFFFFFF;
  }

  /// REAL: Write one PNG chunk (length + type + data + CRC-32).
  static void _chunk(
      BytesBuilder out, String type, List<int> data) {
    final typeBytes = type.codeUnits;
    out.add(_u32be(data.length));
    out.add(typeBytes);
    out.add(data);
    out.add(_u32be(_crc32([...typeBytes, ...data])));
  }

  /// REAL: CRC-32 (IEEE) for PNG chunk checksums.
  static int _crc32(List<int> data) {
    var crc = 0xFFFFFFFF;
    for (final byte in data) {
      crc ^= byte;
      for (var i = 0; i < 8; i++) {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
      }
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  /// REAL: Encode [v] as 4 big-endian bytes.
  static List<int> _u32be(int v) =>
      [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];
}
