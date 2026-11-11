import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:docuray/models/models.dart';
import 'package:docuray/core/services/jpeg_metadata.dart';
import 'package:docuray/core/services/perspective_transform.dart';
import 'package:docuray/core/providers/editor_provider.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1. JpegMetadata Header & Orientation Extraction', () {
    test('Correctly extracts dimensions and orientation from synthetic JPEG header', () {
      // Build a minimal valid JPEG with SOF0 (640x480)
      final bytes = Uint8List.fromList([
        0xFF, 0xD8, // SOI
        // APP1 with EXIF orientation 6 (90° CW)
        0xFF, 0xE1, 0x00, 0x1E,
        0x45, 0x78, 0x69, 0x66, 0x00, 0x00, // 'Exif\0\0'
        0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00, // TIFF little-endian
        0x01, 0x00, // 1 entry
        0x12, 0x01, 0x03, 0x00, 0x01, 0x00, 0x00, 0x00, 0x06, 0x00, 0x00, 0x00, // Orientation = 6
        0x00, 0x00, 0x00, 0x00,
        // SOF0 (height = 480, width = 640)
        0xFF, 0xC0, 0x00, 0x11, 0x08,
        (480 >> 8) & 0xFF, 480 & 0xFF,
        (640 >> 8) & 0xFF, 640 & 0xFF,
        0x03, 0x01, 0x11, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01,
        // EOI
        0xFF, 0xD9,
      ]);

      final meta = JpegMetadata.fromBytes(bytes);
      expect(meta, isNotNull);
      expect(meta!.width, equals(640));
      expect(meta!.height, equals(480));
      expect(meta.orientation, equals(6));
      expect(meta.isRotated90, isTrue);
      expect(meta.uprightWidth, equals(480));
      expect(meta.uprightHeight, equals(640));
      expect(meta.uprightAspectRatio, closeTo(480 / 640, 0.001));
    });
  });

  group('2. Exact Corner Transfer to Editor', () {
    test('EditorProvider receives exact 4 detected corners without altering order', () {
      final editor = EditorProvider();

      final detectedCorners = [
        const CornerPoint(0.12, 0.15),
        const CornerPoint(0.88, 0.14),
        const CornerPoint(0.85, 0.92),
        const CornerPoint(0.10, 0.89),
      ];

      final page = DocumentPage(
        id: 'test_page_1',
        pageNumber: 1,
        corners: detectedCorners,
        autoDetectedCorners: detectedCorners,
        filterType: 'auto',
      );

      editor.initializeWithPages([page]);

      expect(editor.cornerPoints.length, equals(4));
      expect(editor.cornerPoints[0].dx, closeTo(0.12, 1e-4));
      expect(editor.cornerPoints[0].dy, closeTo(0.15, 1e-4));
      expect(editor.cornerPoints[1].dx, closeTo(0.88, 1e-4));
      expect(editor.cornerPoints[1].dy, closeTo(0.14, 1e-4));
      expect(editor.cornerPoints[2].dx, closeTo(0.85, 1e-4));
      expect(editor.cornerPoints[2].dy, closeTo(0.92, 1e-4));
      expect(editor.cornerPoints[3].dx, closeTo(0.10, 1e-4));
      expect(editor.cornerPoints[3].dy, closeTo(0.89, 1e-4));

      // Reset crop restores the exact auto-detected corners
      editor.updateCornerPoint(0, const Offset(0.0, 0.0));
      expect(editor.cornerPoints[0].dx, closeTo(0.0, 1e-4));
      editor.resetCrop();
      expect(editor.cornerPoints[0].dx, closeTo(0.12, 1e-4));
      expect(editor.cornerPoints[0].dy, closeTo(0.15, 1e-4));
    });
  });

  group('3. Perspective Transform preserves exact corners and proportions', () {
    test('PerspectiveTransform.warp maintains non-stretched aspect ratio', () {
      final testImg = img.Image(width: 400, height: 600);
      img.fill(testImg, color: img.ColorRgb8(240, 240, 240));

      // Document occupying 80% width and 80% height centered
      final corners = [
        const CornerPoint(0.1, 0.1),
        const CornerPoint(0.9, 0.1),
        const CornerPoint(0.9, 0.9),
        const CornerPoint(0.1, 0.9),
      ];

      final warped = PerspectiveTransform.warp(source: testImg, corners: corners);

      // Expected output width = 400 * 0.8 = 320, height = 600 * 0.8 = 480
      expect(warped.width, equals(320));
      expect(warped.height, equals(480));
      expect(warped.width / warped.height, closeTo(320 / 480, 0.01));
    });
  });
}

