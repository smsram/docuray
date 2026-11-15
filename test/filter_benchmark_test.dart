import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:docuray/core/services/image_enhancer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  img.Image createTestDoc() {
    const w = 180;
    const h = 240;
    final image = img.Image(width: w, height: h);

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final shadow = (x / w * 0.4 + y / h * 0.6);
        final base = (240.0 - shadow * 100.0).round().clamp(100, 245);
        image.setPixelRgb(x, y, base, (base * 0.96).round(), (base * 0.90).round());
      }
    }

    // Black text
    for (int y = 30; y < 60; y += 6) {
      for (int x = 20; x < 160; x++) {
        image.setPixelRgb(x, y, 20, 20, 20);
      }
    }

    // Faint pencil
    for (int y = 80; y < 110; y += 8) {
      for (int x = 20; x < 140; x++) {
        image.setPixelRgb(x, y, 160, 160, 160);
      }
    }

    // Red annotation
    for (int y = 130; y < 160; y++) {
      for (int x = 20; x < 50; x++) {
        image.setPixelRgb(x, y, 210, 30, 30);
      }
    }

    // Blue signature
    for (int y = 180; y < 200; y++) {
      for (int x = 30; x < 90; x++) {
        image.setPixelRgb(x, y, 25, 45, 195);
      }
    }

    return image;
  }

  group('OpenCV Document Scanner Filter Verification', () {
    late img.Image doc;

    setUp(() {
      doc = createTestDoc();
    });

    test('Levels stretch precomputation matches gamma math', () {
      final lut = ImageEnhancer.buildLevelsLut(25, 238, 1.45);
      expect(lut.length, equals(256));
      expect(lut[0], equals(0)); // below black point
      expect(lut[25], equals(0)); // at black point
      expect(lut[238], equals(255)); // at white point
      expect(lut[255], equals(255)); // above white point

      // Mid-tone check: gamma > 1.0 darkens ink density (increases readability)
      final normMid = (128 - 25) / (238 - 25);
      final inkMid = math.pow(1.0 - normMid, 1.0 / 1.45);
      final expectedMid = ((1.0 - inkMid) * 255.0).round();
      expect(lut[128], equals(expectedMid));
    });

    test('Two-pass getCleanBackground estimates illumination and clamps to >= 15', () {
      final rgb = doc.getBytes(order: img.ChannelOrder.rgb);
      final gray = Uint8List(doc.width * doc.height);
      for (int i = 0; i < gray.length; i++) {
        gray[i] = (0.299 * rgb[i * 3] + 0.587 * rgb[i * 3 + 1] + 0.114 * rgb[i * 3 + 2]).round();
      }

      final bg = ImageEnhancer.getCleanBackground(gray, doc.width, doc.height);
      expect(bg.length, equals(doc.width * doc.height));

      // Minimum clamped to 15
      for (int i = 0; i < bg.length; i++) {
        expect(bg[i], greaterThanOrEqualTo(15));
      }

      // Background under dark text (x=50, y=40) should estimate paper luminance, not text
      final textBg = bg[40 * doc.width + 50];
      expect(textBg, greaterThanOrEqualTo(180));
    });

    test('Auto-Color produces brightened paper and preserves ink colors', () {
      final autoColor = ImageEnhancer.process(source: doc, filterType: 'auto');
      expect(autoColor.width, equals(doc.width));
      expect(autoColor.height, equals(doc.height));

      // Red stamp annotation retains red dominance
      final red = autoColor.getPixel(25, 145);
      expect(red.r, greaterThan(red.g));
      expect(red.r, greaterThan(red.b));

      // Blue ink signature retains blue dominance
      final blue = autoColor.getPixel(50, 190);
      expect(blue.b, greaterThan(blue.r + 50));
      expect(blue.b, greaterThan(blue.g + 50));
    });

    test('Light Text enhances faint handwriting strokes', () {
      final lightText = ImageEnhancer.process(source: doc, filterType: 'light_text');
      final rawPencil = doc.getPixel(50, 96);
      final procPencil = lightText.getPixel(50, 96);

      final rawLum = 0.299 * rawPencil.r + 0.587 * rawPencil.g + 0.114 * rawPencil.b;
      final procLum = 0.299 * procPencil.r + 0.587 * procPencil.g + 0.114 * procPencil.b;
      expect(procLum, lessThan(rawLum));
    });

    test('Grayscale produces strictly monochrome output with R == G == B', () {
      final gray = ImageEnhancer.process(source: doc, filterType: 'grayscale');
      for (int y = 0; y < gray.height; y += 20) {
        for (int x = 0; x < gray.width; x += 20) {
          final p = gray.getPixel(x, y);
          expect(p.r, equals(p.g));
          expect(p.g, equals(p.b));
        }
      }
    });

    test('Whiteboard produces high contrast whitened background and boosted ink', () {
      final wb = ImageEnhancer.process(source: doc, filterType: 'whiteboard');
      final bg = wb.getPixel(150, 20);
      expect(bg.r, greaterThanOrEqualTo(235));
      expect(bg.g, greaterThanOrEqualTo(235));
      expect(bg.b, greaterThanOrEqualTo(235));
    });

    test('Black & White produces high-contrast document without shadow patches', () {
      final bw = ImageEnhancer.process(source: doc, filterType: 'bw');
      // Shadow corner paper background is bright
      final shadowPaper = bw.getPixel(160, 220);
      expect(shadowPaper.r, greaterThanOrEqualTo(240));

      // Dark text is dark
      final text = bw.getPixel(50, 48);
      expect(text.r, lessThanOrEqualTo(25));
    });
  });
}
