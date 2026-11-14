import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:docuray/models/models.dart';
import 'package:docuray/core/providers/editor_provider.dart';
import 'package:docuray/core/services/corner_detector_service.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Gallery Image Detection & Dimensions Pipeline', () {
    test('detectCornersFromPath executes safely on static image file', () async {
      final detector = PaperCornerDetector();

      // Create a synthetic image of a document (white sheet) on a dark desk
      final testImage = img.Image(width: 800, height: 1200);
      img.fill(testImage, color: img.ColorRgb8(30, 30, 30));

      for (int y = 200; y < 1000; y++) {
        for (int x = 100; x < 700; x++) {
          testImage.setPixelRgb(x, y, 240, 240, 240);
        }
      }

      final tempDir = Directory.systemTemp.createTempSync('docuray_test_');
      final testFile = File('${tempDir.path}/test_doc.jpg');
      await testFile.writeAsBytes(img.encodeJpg(testImage));

      try {
        final result = await detector.detectCornersFromPath(testFile.path);
        expect(result, isNotNull);
        expect(result.corners.length, equals(4));
      } finally {
        detector.dispose();
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    });

    test('DocumentPage computes exact aspect ratio from imageWidth and imageHeight', () {
      const pageWithDims = DocumentPage(
        id: 'p1',
        pageNumber: 1,
        imageWidth: 3000,
        imageHeight: 4000,
      );
      expect(pageWithDims.aspectRatio, closeTo(3000 / 4000, 1e-5));

      const pageWithLandscape = DocumentPage(
        id: 'p2',
        pageNumber: 1,
        imageWidth: 1920,
        imageHeight: 1080,
      );
      expect(pageWithLandscape.aspectRatio, closeTo(1920 / 1080, 1e-5));

      const pageWithoutDims = DocumentPage(
        id: 'p3',
        pageNumber: 1,
      );
      expect(pageWithoutDims.aspectRatio, closeTo(3.0 / 4.0, 1e-5));
    });

    test('DocumentPage serialization preserves imageWidth and imageHeight', () {
      const original = DocumentPage(
        id: 'p1',
        pageNumber: 1,
        imageWidth: 2400,
        imageHeight: 3200,
      );

      final json = original.toJson();
      expect(json['imageWidth'], equals(2400));
      expect(json['imageHeight'], equals(3200));

      final restored = DocumentPage.fromJson(json);
      expect(restored.imageWidth, equals(2400));
      expect(restored.imageHeight, equals(3200));
      expect(restored.aspectRatio, equals(original.aspectRatio));
    });

    test('EditorProvider initializes in crop mode when autoDetectedCorners is null', () {
      final editor = EditorProvider();

      const manualPage = DocumentPage(
        id: 'manual_1',
        pageNumber: 1,
        corners: [
          CornerPoint(0.0, 0.0),
          CornerPoint(1.0, 0.0),
          CornerPoint(1.0, 1.0),
          CornerPoint(0.0, 1.0),
        ],
        autoDetectedCorners: null,
      );

      editor.initializeWithPages([manualPage]);
      expect(editor.activeTool, equals(EditorActiveTool.crop));

      const autoDetectedPage = DocumentPage(
        id: 'auto_1',
        pageNumber: 1,
        corners: [
          CornerPoint(0.1, 0.1),
          CornerPoint(0.9, 0.1),
          CornerPoint(0.9, 0.9),
          CornerPoint(0.1, 0.9),
        ],
        autoDetectedCorners: [
          CornerPoint(0.1, 0.1),
          CornerPoint(0.9, 0.1),
          CornerPoint(0.9, 0.9),
          CornerPoint(0.1, 0.9),
        ],
      );

      editor.initializeWithPages([autoDetectedPage]);
      expect(editor.activeTool, equals(EditorActiveTool.none));
    });

    test('EditorProvider addPage opens crop tool if first page lacks auto-detection', () {
      final editor = EditorProvider();
      editor.clearPages();

      const manualPage = DocumentPage(
        id: 'manual_add_1',
        pageNumber: 1,
        autoDetectedCorners: null,
      );

      editor.addPage(manualPage);
      expect(editor.activeTool, equals(EditorActiveTool.crop));
    });
  });
}
