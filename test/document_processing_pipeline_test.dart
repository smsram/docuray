import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:docuray/models/models.dart';
import 'package:docuray/core/services/image_enhancer.dart';
import 'package:docuray/core/services/perspective_transform.dart';
import 'package:docuray/core/services/pdf_generator_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Creates a synthetic document image simulating real-world scanning conditions:
  /// - Paper with uneven lighting / desk shadow gradient across the page
  /// - Black printed text
  /// - Faint pencil writing (low contrast gray midtones)
  /// - Colored annotations (red margin note, blue signature, yellow highlight)
  img.Image createTestDocumentImage({int width = 400, int height = 600}) {
    final image = img.Image(width: width, height: height);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        // Uneven lighting gradient: 240 (bright top-left) to 130 (dark shadow bottom-right)
        final shadow = (x / width * 0.4 + y / height * 0.6);
        final paperBase = (240.0 - shadow * 100.0).round().clamp(110, 245);
        // Subtle warm paper color cast (slight yellow/sepia)
        image.setPixelRgb(x, y, paperBase, (paperBase * 0.96).round(), (paperBase * 0.90).round());
      }
    }

    // 1. Black printed text (lines 50 to 90)
    for (int y = 50; y < 90; y += 8) {
      for (int x = 40; x < 360; x++) {
        if ((x % 16) < 12) {
          image.setPixelRgb(x, y, 20, 20, 20);
          image.setPixelRgb(x, y + 1, 20, 20, 20);
        }
      }
    }

    // 2. Faint pencil writing (lines 140 to 180) - pale midtone gray
    for (int y = 140; y < 180; y += 10) {
      for (int x = 40; x < 300; x++) {
        image.setPixelRgb(x, y, 165, 165, 165);
      }
    }

    // 3. Colored annotations:
    // Red margin note (x: 20 to 30, y: 220 to 280)
    for (int y = 220; y < 280; y++) {
      for (int x = 20; x < 30; x++) {
        image.setPixelRgb(x, y, 210, 30, 30);
      }
    }

    // Blue pen signature (x: 50 to 150, y: 320 to 335)
    for (int y = 320; y < 335; y++) {
      for (int x = 50; x < 150; x++) {
        image.setPixelRgb(x, y, 25, 45, 195);
      }
    }

    // Yellow highlighter over text (x: 50 to 220, y: 380 to 400)
    for (int y = 380; y < 400; y++) {
      for (int x = 50; x < 220; x++) {
        // Semi-transparent yellow wash
        image.setPixelRgb(x, y, 250, 240, 60);
      }
    }

    return image;
  }

  group('Section 3 & 4: Professional Document Filters & Illumination Correction', () {
    late img.Image testDoc;

    setUp(() {
      testDoc = createTestDocumentImage();
    });

    test('1. ORIGINAL preset preserves raw pixels, colors, and tonal appearance', () {
      final original = ImageEnhancer.process(source: testDoc, filterType: 'original');

      expect(original.width, equals(testDoc.width));
      expect(original.height, equals(testDoc.height));

      // Sampling points across image to confirm identical values
      final sampleCoords = [
        (50, 50),
        (150, 150),
        (25, 250),
        (100, 325),
        (100, 390),
      ];

      for (final (x, y) in sampleCoords) {
        final origPixel = testDoc.getPixel(x, y);
        final procPixel = original.getPixel(x, y);
        expect(procPixel.r, equals(origPixel.r));
        expect(procPixel.g, equals(origPixel.g));
        expect(procPixel.b, equals(origPixel.b));
      }
    });

    test('2. AUTO-COLOR normalizes shadows while preserving colored ink and highlights', () {
      final autoColor = ImageEnhancer.process(source: testDoc, filterType: 'auto');

      // (a) Paper background in shadow area (bottom-right: x=350, y=550) should be brightened
      final rawShadowPaper = testDoc.getPixel(350, 550);
      final procShadowPaper = autoColor.getPixel(350, 550);
      expect(procShadowPaper.r, greaterThan(rawShadowPaper.r));
      expect(procShadowPaper.g, greaterThan(rawShadowPaper.g));
      expect(procShadowPaper.b, greaterThan(rawShadowPaper.b));

      // (b) Red marker ink (x=25, y=250) must retain strong red saturation (chroma protection)
      final redPixel = autoColor.getPixel(25, 250);
      expect(redPixel.r, greaterThan(redPixel.g + 80));
      expect(redPixel.r, greaterThan(redPixel.b + 80));

      // (c) Blue signature (x=70, y=325) must retain blue ink color
      final bluePixel = autoColor.getPixel(70, 325);
      expect(bluePixel.b, greaterThan(bluePixel.r + 50));
      expect(bluePixel.b, greaterThan(bluePixel.g + 50));

      // (d) Yellow highlighter (x=100, y=390) must retain yellow hue
      final yellowPixel = autoColor.getPixel(100, 390);
      expect(yellowPixel.r, greaterThan(200));
      expect(yellowPixel.g, greaterThan(180));
      expect(yellowPixel.b, lessThan(yellowPixel.r - 80));
    });

    test('3. LIGHT TEXT enhances faint handwriting and brightens background', () {
      final lightText = ImageEnhancer.process(source: testDoc, filterType: 'light_text');

      // (a) Background paper should be clean and bright (> 240)
      final bgPixel = lightText.getPixel(200, 20);
      expect(bgPixel.r, greaterThanOrEqualTo(240));
      expect(bgPixel.g, greaterThanOrEqualTo(240));

      // (b) Faint pencil stroke (x=50, y=140) should be darkened for readability
      final rawPencil = testDoc.getPixel(50, 140);
      final procPencil = lightText.getPixel(50, 140);
      // Pencil luminance should be darker (lower value) than raw
      final rawLum = 0.299 * rawPencil.r + 0.587 * rawPencil.g + 0.114 * rawPencil.b;
      final procLum = 0.299 * procPencil.r + 0.587 * procPencil.g + 0.114 * procPencil.b;
      expect(procLum, lessThan(rawLum));
    });

    test('4. GRAYSCALE converts correctly to monochrome using Rec.601 luminance', () {
      final grayscale = ImageEnhancer.process(source: testDoc, filterType: 'grayscale');

      // Every pixel must have R == G == B (strictly monochrome)
      for (int y = 0; y < grayscale.height; y += 40) {
        for (int x = 0; x < grayscale.width; x += 40) {
          final p = grayscale.getPixel(x, y);
          expect(p.r, equals(p.g));
          expect(p.g, equals(p.b));
        }
      }
    });

    test('5. WHITEBOARD normalizes board reflections and boosts marker visibility', () {
      final whiteboard = ImageEnhancer.process(source: testDoc, filterType: 'whiteboard');

      // Board background is whitened
      final boardPixel = whiteboard.getPixel(200, 20);
      expect(boardPixel.r, greaterThanOrEqualTo(235));
      expect(boardPixel.g, greaterThanOrEqualTo(235));

      // Red marker is boosted
      final redPixel = whiteboard.getPixel(25, 250);
      expect(redPixel.r, greaterThan(redPixel.g + 90));

      // Blue marker is boosted
      final bluePixel = whiteboard.getPixel(70, 325);
      expect(bluePixel.b, greaterThan(bluePixel.r + 60));
    });

    test('6. BLACK & WHITE with Sauvola local thresholding is binary and avoids shadow blotches', () {
      final bw = ImageEnhancer.process(source: testDoc, filterType: 'bw');

      // (a) All pixels must be strictly binary: 0 or 255
      for (int y = 0; y < bw.height; y += 30) {
        for (int x = 0; x < bw.width; x += 30) {
          final p = bw.getPixel(x, y);
          expect(p.r == 0 || p.r == 255, isTrue);
          expect(p.r, equals(p.g));
          expect(p.g, equals(p.b));
        }
      }

      // (b) Shadow area paper background (x=350, y=550) must NOT turn black!
      // Sauvola local standard deviation adaptation prevents false shadow blotches.
      final shadowBgPixel = bw.getPixel(350, 550);
      expect(shadowBgPixel.r, equals(255)); // White paper

      // (c) Dark printed text stroke (x=50, y=50) must be 0 (black text)
      final textPixel = bw.getPixel(50, 50);
      expect(textPixel.r, equals(0));
    });

    test('7. All six filter presets produce genuinely different, appropriate results', () {
      final pOrig = ImageEnhancer.process(source: testDoc, filterType: 'original');
      final pAuto = ImageEnhancer.process(source: testDoc, filterType: 'auto');
      final pLight = ImageEnhancer.process(source: testDoc, filterType: 'light_text');
      final pGray = ImageEnhancer.process(source: testDoc, filterType: 'grayscale');
      final pWhite = ImageEnhancer.process(source: testDoc, filterType: 'whiteboard');
      final pBw = ImageEnhancer.process(source: testDoc, filterType: 'bw');

      // Compare pixel sums across the image to confirm uniqueness
      int sumOrig = 0, sumAuto = 0, sumLight = 0, sumGray = 0, sumWhite = 0, sumBw = 0;
      for (int y = 0; y < testDoc.height; y += 10) {
        for (int x = 0; x < testDoc.width; x += 10) {
          sumOrig += pOrig.getPixel(x, y).r.toInt();
          sumAuto += pAuto.getPixel(x, y).r.toInt();
          sumLight += pLight.getPixel(x, y).r.toInt();
          sumGray += pGray.getPixel(x, y).r.toInt();
          sumWhite += pWhite.getPixel(x, y).r.toInt();
          sumBw += pBw.getPixel(x, y).r.toInt();
        }
      }

      final sums = {sumOrig, sumAuto, sumLight, sumGray, sumWhite, sumBw};
      // Every preset produces distinct tonal output
      expect(sums.length, equals(6));
    });

    test('8. Filter switching is non-destructive (never stacks edits on previous results)', () {
      // First apply B&W
      final bw1 = ImageEnhancer.process(source: testDoc, filterType: 'bw');
      expect(bw1.getPixel(50, 50).r, equals(0));

      // Switching to Original must restore colors from the source, NOT stack on B&W
      final restoredOrig = ImageEnhancer.process(source: testDoc, filterType: 'original');
      final redSample = restoredOrig.getPixel(25, 250);
      expect(redSample.r, equals(210));
      expect(redSample.g, equals(30));
      expect(redSample.b, equals(30));
    });
  });

  group('Section 5: Denoising and Halo-Free Sharpening', () {
    test('Sharpening enhances text edges without introducing white halos or extreme noise amplification', () {
      final imgTest = img.Image(width: 100, height: 100);
      // Flat background with a dark step edge
      for (int y = 0; y < 100; y++) {
        for (int x = 0; x < 100; x++) {
          imgTest.setPixelRgb(x, y, x < 50 ? 200 : 80, x < 50 ? 200 : 80, x < 50 ? 200 : 80);
        }
      }

      final sharpened = ImageEnhancer.process(source: imgTest, filterType: 'original', sharpness: 0.5);

      // Sharpness should increase gradient across edge
      final beforeEdge = sharpened.getPixel(48, 50).r;
      final afterEdge = sharpened.getPixel(51, 50).r;
      expect(beforeEdge - afterEdge, greaterThanOrEqualTo(120));

      // But should not blow out background pixels far from the edge (no ringing/halo artifacts)
      final farLeft = sharpened.getPixel(10, 50).r;
      expect(farLeft, equals(200));
    });
  });

  group('Section 6 & 7: Perspective Transformation, Homography, and Corner Sorting', () {
    test('sortCorners correctly arranges arbitrary 4 points in TL, TR, BR, BL order', () {
      // Permuted input corners
      final rawCorners = [
        const CornerPoint(0.85, 0.90), // BR
        const CornerPoint(0.10, 0.15), // TL
        const CornerPoint(0.12, 0.88), // BL
        const CornerPoint(0.88, 0.12), // TR
      ];

      final sorted = PerspectiveTransform.sortCorners(rawCorners);

      expect(sorted.length, equals(4));
      // Top-Left (x low, y low)
      expect(sorted[0].x, closeTo(0.10, 0.02));
      expect(sorted[0].y, closeTo(0.15, 0.02));

      // Top-Right (x high, y low)
      expect(sorted[1].x, closeTo(0.88, 0.02));
      expect(sorted[1].y, closeTo(0.12, 0.02));

      // Bottom-Right (x high, y high)
      expect(sorted[2].x, closeTo(0.85, 0.02));
      expect(sorted[2].y, closeTo(0.90, 0.02));

      // Bottom-Left (x low, y high)
      expect(sorted[3].x, closeTo(0.12, 0.02));
      expect(sorted[3].y, closeTo(0.88, 0.02));
    });

    test('isValidQuad accepts valid convex quads and rejects degenerate/collinear points', () {
      final valid = [
        const CornerPoint(0.1, 0.1),
        const CornerPoint(0.9, 0.1),
        const CornerPoint(0.9, 0.9),
        const CornerPoint(0.1, 0.9),
      ];
      expect(PerspectiveTransform.isValidQuad(valid), isTrue);

      // Collinear / degenerate quad
      final collinear = [
        const CornerPoint(0.1, 0.1),
        const CornerPoint(0.5, 0.5),
        const CornerPoint(0.9, 0.9),
        const CornerPoint(0.1, 0.9),
      ];
      expect(PerspectiveTransform.isValidQuad(collinear), isFalse);
    });

    test('PerspectiveTransform.warp straightens quadrilateral and preserves aspect ratio', () {
      final src = img.Image(width: 400, height: 600);
      for (int y = 0; y < 600; y++) {
        for (int x = 0; x < 400; x++) {
          src.setPixelRgb(x, y, 220, 220, 220);
        }
      }

      // Slightly rotated / perspective quad inside src
      final corners = [
        const CornerPoint(0.15, 0.10), // TL
        const CornerPoint(0.85, 0.15), // TR
        const CornerPoint(0.80, 0.90), // BR
        const CornerPoint(0.10, 0.85), // BL
      ];

      final warped = PerspectiveTransform.warp(source: src, corners: corners);

      // Warped image dimensions should match quadrilateral width & height
      expect(warped.width, greaterThan(240));
      expect(warped.height, greaterThan(400));
      expect(warped.width, lessThan(400));
      expect(warped.height, lessThan(600));
    });
  });

  group('Section 8: PDF Export Quality Presets and Multi-Page Document Sizing', () {
    test('PdfExportQuality presets have strictly increasing target DPI and compression quality', () {
      expect(PdfExportQuality.small.targetDpi, equals(150));
      expect(PdfExportQuality.standard.targetDpi, equals(200));
      expect(PdfExportQuality.high.targetDpi, equals(300));

      expect(PdfExportQuality.small.jpegQuality, lessThan(PdfExportQuality.standard.jpegQuality));
      expect(PdfExportQuality.standard.jpegQuality, lessThan(PdfExportQuality.high.jpegQuality));

      expect(PdfExportQuality.small.maxDimension, lessThan(PdfExportQuality.standard.maxDimension));
      expect(PdfExportQuality.standard.maxDimension, lessThan(PdfExportQuality.high.maxDimension));
    });

    test('PdfExportQuality.fromString correctly parses preset names', () {
      expect(PdfExportQuality.fromString('small'), equals(PdfExportQuality.small));
      expect(PdfExportQuality.fromString('Standard'), equals(PdfExportQuality.standard));
      expect(PdfExportQuality.fromString('HIGH'), equals(PdfExportQuality.high));
      expect(PdfExportQuality.fromString('invalid'), equals(PdfExportQuality.standard));
    });

    test('PdfGeneratorService creates valid PDFs where Small < Standard < High file size', () async {
      final tempDir = await Directory.systemTemp.createTemp('docuray_pdf_test_');

      // Create a test page image file
      final pageImg = createTestDocumentImage(width: 800, height: 1200);
      final imgPath = '${tempDir.path}/test_page.jpg';
      await File(imgPath).writeAsBytes(img.encodeJpg(pageImg, quality: 95));

      final testPage = DocumentPage(
        id: 'page_1',
        pageNumber: 1,
        originalImagePath: imgPath,
        processedImagePath: imgPath,
        filterType: 'auto',
      );

      final smallPdfPath = '${tempDir.path}/small.pdf';
      final standardPdfPath = '${tempDir.path}/standard.pdf';
      final highPdfPath = '${tempDir.path}/high.pdf';

      final fileSmall = await PdfGeneratorService.generatePdf(
        pages: [testPage],
        outputPath: smallPdfPath,
        quality: PdfExportQuality.small,
      );

      final fileStandard = await PdfGeneratorService.generatePdf(
        pages: [testPage],
        outputPath: standardPdfPath,
        quality: PdfExportQuality.standard,
      );

      final fileHigh = await PdfGeneratorService.generatePdf(
        pages: [testPage],
        outputPath: highPdfPath,
        quality: PdfExportQuality.high,
      );

      final sizeSmall = await fileSmall.length();
      final sizeStandard = await fileStandard.length();
      final sizeHigh = await fileHigh.length();

      // All PDFs exist and are valid non-empty PDF files (> 10 KB)
      expect(sizeSmall, greaterThan(10 * 1024));
      expect(sizeStandard, greaterThan(10 * 1024));
      expect(sizeHigh, greaterThan(10 * 1024));

      // Small file size < Standard file size < High file size
      expect(sizeSmall, lessThan(sizeStandard));
      expect(sizeStandard, lessThan(sizeHigh));

      // Clean up temp dir
      await tempDir.delete(recursive: true);
    });

    test('formatFileSize correctly formats bytes into readable units', () {
      expect(PdfGeneratorService.formatFileSize(512), equals('512 B'));
      expect(PdfGeneratorService.formatFileSize(450 * 1024), equals('450.0 KB'));
      expect(PdfGeneratorService.formatFileSize((2.5 * 1024 * 1024).toInt()), equals('2.5 MB'));
    });
  });
}
