import 'dart:io';
import 'dart:typed_data';

/// Fast, non-decoding parser for JPEG image dimensions and EXIF orientation tag.
/// Reads only the first few kilobytes of the file header to avoid loading 12MP+ bitmaps into memory.
class JpegMetadata {
  final int width;
  final int height;
  final int orientation; // EXIF orientation tag: 1 = 0°, 6 = 90° CW, 3 = 180°, 8 = 270° CW

  const JpegMetadata({
    required this.width,
    required this.height,
    this.orientation = 1,
  });

  bool get isRotated90 => orientation == 6 || orientation == 8;
  int get uprightWidth => isRotated90 ? height : width;
  int get uprightHeight => isRotated90 ? width : height;
  double get uprightAspectRatio => uprightWidth / uprightHeight;

  /// Parses JPEG header directly from a file without loading the full image into memory.
  static Future<JpegMetadata?> fromFile(File file) async {
    try {
      if (!await file.exists()) return null;
      final raf = await file.open(mode: FileMode.read);
      try {
        final header = await raf.read(65536); // 64KB contains APP1 (EXIF) and SOF0
        return fromBytes(header);
      } finally {
        await raf.close();
      }
    } catch (_) {
      return null;
    }
  }

  /// Parses JPEG markers from byte buffer.
  static JpegMetadata? fromBytes(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;

    int offset = 2;
    int orientation = 1;
    int width = 0;
    int height = 0;

    while (offset + 4 < bytes.length) {
      if (bytes[offset] != 0xFF) {
        offset++;
        continue;
      }
      final marker = bytes[offset + 1];
      offset += 2;

      // End of image (EOI) or Start of Scan (SOS - image entropy data begins)
      if (marker == 0xD9 || marker == 0xDA) break;

      if (offset + 2 > bytes.length) break;
      final length = (bytes[offset] << 8) | bytes[offset + 1];
      if (length < 2 || offset + length > bytes.length) break;

      // SOF0 (0xC0), SOF1 (0xC1), SOF2 (0xC2) - Start of Frame contains dimensions
      if (marker == 0xC0 || marker == 0xC1 || marker == 0xC2) {
        if (length >= 7) {
          height = (bytes[offset + 3] << 8) | bytes[offset + 4];
          width = (bytes[offset + 5] << 8) | bytes[offset + 6];
        }
      }
      // APP1 (0xE1) - May contain EXIF header
      else if (marker == 0xE1 && length >= 14) {
        if (bytes[offset + 2] == 0x45 && // 'E'
            bytes[offset + 3] == 0x78 && // 'x'
            bytes[offset + 4] == 0x69 && // 'i'
            bytes[offset + 5] == 0x66 && // 'f'
            bytes[offset + 6] == 0x00 &&
            bytes[offset + 7] == 0x00) {
          final tiffStart = offset + 8;
          if (tiffStart + 8 <= bytes.length) {
            final isLittleEndian = bytes[tiffStart] == 0x49 && bytes[tiffStart + 1] == 0x49;

            int read16(int p) {
              if (p + 1 >= bytes.length) return 0;
              return isLittleEndian
                  ? (bytes[p] | (bytes[p + 1] << 8))
                  : ((bytes[p] << 8) | bytes[p + 1]);
            }

            int read32(int p) {
              if (p + 3 >= bytes.length) return 0;
              return isLittleEndian
                  ? (bytes[p] | (bytes[p + 1] << 8) | (bytes[p + 2] << 16) | (bytes[p + 3] << 24))
                  : ((bytes[p] << 24) | (bytes[p + 1] << 16) | (bytes[p + 2] << 8) | bytes[p + 3]);
            }

            final ifdOffset = read32(tiffStart + 4);
            if (ifdOffset >= 0 && tiffStart + ifdOffset + 2 <= bytes.length) {
              final numEntries = read16(tiffStart + ifdOffset);
              var entryPtr = tiffStart + ifdOffset + 2;
              for (int e = 0; e < numEntries; e++) {
                if (entryPtr + 12 > bytes.length) break;
                final tag = read16(entryPtr);
                if (tag == 0x0112) { // Orientation tag
                  orientation = read16(entryPtr + 8);
                  break;
                }
                entryPtr += 12;
              }
            }
          }
        }
      }

      if (width > 0 && height > 0 && orientation != 1) break;
      offset += length;
    }

    if (width > 0 && height > 0) {
      return JpegMetadata(width: width, height: height, orientation: orientation);
    }
    return null;
  }
}

