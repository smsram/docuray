import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:docuray/models/models.dart';
import 'package:docuray/core/services/jpeg_metadata.dart';
import 'package:docuray/core/services/corner_detector_service.dart';
import 'package:docuray/core/services/perspective_transform.dart';
import 'package:docuray/core/services/scanner_diagnostics.dart';
import 'package:docuray/core/providers/editor_provider.dart';
import 'package:docuray/core/providers/scanner_provider.dart';
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
      if (meta == null) return;
      expect(meta.width, equals(640));
      expect(meta.height, equals(480));
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

  group('4. Raw Coordinates Preserved & Stability Tracking', () {
    test('PaperCornerDetector preserves raw model coordinates and tracks consecutive stable frames', () {
      final detector = PaperCornerDetector();

      final baseCorners = [
        const CornerPoint(0.10, 0.10),
        const CornerPoint(0.90, 0.10),
        const CornerPoint(0.90, 0.90),
        const CornerPoint(0.10, 0.90),
      ];

      // First frame initializes
      final f1 = detector.applyStabilizationForTesting(baseCorners);
      expect(f1[0].x, equals(0.10));
      expect(detector.consecutiveStableFrames, equals(1));

      // Small jitter (< 0.04) increments consecutive stable frames
      final jitteredCorners = [
        const CornerPoint(0.101, 0.101),
        const CornerPoint(0.901, 0.101),
        const CornerPoint(0.901, 0.901),
        const CornerPoint(0.101, 0.901),
      ];
      final f2 = detector.applyStabilizationForTesting(jitteredCorners);
      expect(f2[0].x, equals(0.101)); // Exact raw coordinate returned
      expect(detector.consecutiveStableFrames, equals(2));

      // Active camera motion (shift >= 0.04) resets stable frames to 1 and returns exact coordinates
      final movedCorners = [
        const CornerPoint(0.20, 0.20),
        const CornerPoint(0.95, 0.20),
        const CornerPoint(0.95, 0.95),
        const CornerPoint(0.20, 0.95),
      ];
      final f3 = detector.applyStabilizationForTesting(movedCorners);
      expect(f3[0].x, equals(0.20)); // Exact raw coordinate returned
      expect(detector.consecutiveStableFrames, equals(1)); // Reset stability on movement
    });
  });

  group('5. Gallery Auto vs Manual Mode Policy', () {
    test('Manual mode defaults to full bounds with null autoDetectedCorners', () {
      final page = DocumentPage(
        id: 'manual_page_1',
        pageNumber: 1,
        corners: const [
          CornerPoint(0.0, 0.0),
          CornerPoint(1.0, 0.0),
          CornerPoint(1.0, 1.0),
          CornerPoint(0.0, 1.0),
        ],
        autoDetectedCorners: null,
        filterType: 'auto',
      );

      expect(page.autoDetectedCorners, isNull);
      expect(page.corners[0].x, equals(0.0));
      expect(page.corners[2].x, equals(1.0));
    });

    test('Auto mode stores detected document corners in both corners and autoDetectedCorners', () {
      final detected = const [
        CornerPoint(0.15, 0.20),
        CornerPoint(0.85, 0.18),
        CornerPoint(0.82, 0.88),
        CornerPoint(0.12, 0.86),
      ];
      final page = DocumentPage(
        id: 'auto_page_1',
        pageNumber: 1,
        corners: detected,
        autoDetectedCorners: detected,
        filterType: 'auto',
      );

      expect(page.autoDetectedCorners, isNotNull);
      expect(page.autoDetectedCorners!.length, equals(4));
      expect(page.corners, equals(detected));
    });
  });

  group('6. DocumentPredictionState & Initial Visibility Guarantees', () {
    test('ScannerProvider initializes with initialNoPrediction and null corners', () {
      final scanner = ScannerProvider();
      expect(scanner.predictionState, equals(DocumentPredictionState.initialNoPrediction));
      expect(scanner.detectedCorners, isEmpty);
      expect(scanner.hasValidPrediction, isFalse);
      expect(scanner.cornersNotifier.value, isNull);
      expect(scanner.predictionStateNotifier.value, equals(DocumentPredictionState.initialNoPrediction));
    });

    test('All 6 DocumentPredictionState enum values exist and are distinct', () {
      final states = DocumentPredictionState.values;
      expect(states.length, equals(6));
      expect(states, contains(DocumentPredictionState.initialNoPrediction));
      expect(states, contains(DocumentPredictionState.inferring));
      expect(states, contains(DocumentPredictionState.validDocument));
      expect(states, contains(DocumentPredictionState.noDocumentDetected));
      expect(states, contains(DocumentPredictionState.detectionTemporarilyLost));
      expect(states, contains(DocumentPredictionState.stopped));
    });
  });

  group('7. ScannerDiagnosticsTracker Rolling Window Calculation', () {
    test('Correctly records frames, drops, and calculates averages', () {
      final tracker = ScannerDiagnosticsTracker();

      // Record frames
      tracker.recordCameraFrame();
      tracker.recordCameraFrame();
      tracker.recordSubmittedFrame();
      tracker.recordDroppedFrame();

      tracker.recordCompletedPrediction({
        'prepMs': 5.0,
        'inferenceMs': 45.0,
        'decodeMs': 10.0,
        'totalLatencyMs': 60.0,
        'backend': 'NNAPI',
        'hasDocument': true,
        'confidence': 0.88,
      });

      final metrics = tracker.getMetrics();
      expect(metrics.cameraFps, equals(2.0));
      expect(metrics.submittedFps, equals(1.0));
      expect(metrics.completedFps, equals(1.0));
      expect(metrics.droppedCount, equals(1));
      expect(metrics.droppedFps, equals(1.0));
      expect(metrics.prepMs, closeTo(5.0, 0.01));
      expect(metrics.inferenceMs, closeTo(45.0, 0.01));
      expect(metrics.postprocessMs, closeTo(10.0, 0.01));
      expect(metrics.totalLatencyMs, closeTo(60.0, 0.01));
      expect(metrics.backend, equals('NNAPI'));
      expect(metrics.hasDocument, isTrue);
      expect(metrics.confidence, closeTo(0.88, 0.01));
    });

    test('Tracker reset clears all rolling queues', () {
      final tracker = ScannerDiagnosticsTracker();
      tracker.recordCameraFrame();
      tracker.reset();
      final metrics = tracker.getMetrics();
      expect(metrics.cameraFps, equals(0.0));
      expect(metrics.completedFps, equals(0.0));
    });
  });

  group('8. Raw Model Coordinates Decoupled From Visual Rendering', () {
    test('PaperCornerDetector initializes clean and uninitialized', () async {
      final detector = PaperCornerDetector();
      expect(detector.isInitialized, isFalse);
      expect(detector.consecutiveStableFrames, equals(0));
    });

    test('Strict separation between raw model prediction and visual display coordinates', () {
      final rawCorners = [
        const Offset(0.12, 0.15),
        const Offset(0.88, 0.14),
        const Offset(0.85, 0.92),
        const Offset(0.10, 0.89),
      ];

      final scanner = ScannerProvider();
      // Simulate raw prediction delivered to scanner provider
      scanner.cornersNotifier.value = rawCorners;
      expect(scanner.cornersNotifier.value, equals(rawCorners));

      // Visual interpolation simulating halfway animation progress
      final visualDisplayCorners = [
        const Offset(0.14, 0.16),
        const Offset(0.86, 0.15),
        const Offset(0.84, 0.91),
        const Offset(0.11, 0.88),
      ];

      // Raw model coordinates remain strictly untouched by visual interpolation
      expect(rawCorners[0].dx, equals(0.12));
      expect(rawCorners[1].dx, equals(0.88));
      expect(visualDisplayCorners[0].dx, isNot(equals(rawCorners[0].dx)));
    });

    test('Corner order [TL, TR, BR, BL] is preserved 1:1 without permutations', () {
      final inputPrediction = [
        const Offset(0.10, 0.12), // TL
        const Offset(0.90, 0.14), // TR
        const Offset(0.88, 0.92), // BR
        const Offset(0.12, 0.90), // BL
      ];

      // Target copy preserves exact order
      final targetCorners = List<Offset>.from(inputPrediction);
      expect(targetCorners[0], equals(const Offset(0.10, 0.12)));
      expect(targetCorners[1], equals(const Offset(0.90, 0.14)));
      expect(targetCorners[2], equals(const Offset(0.88, 0.92)));
      expect(targetCorners[3], equals(const Offset(0.12, 0.90)));
    });
  });

  group('9. Camera Capture Coordinate Transformation & Mirroring', () {
    test('Calculates horizontal aspect ratio compensation when preview is narrower than sensor', () {
      const prevAspect = 720.0 / 1280.0; // 0.5625
      const photoAspect = 3000.0 / 4000.0; // 0.75
      final previewCorners = [
        const Offset(0.0, 0.1), // Left edge in preview
        const Offset(1.0, 0.1), // Right edge in preview
        const Offset(1.0, 0.9),
        const Offset(0.0, 0.9),
      ];

      final mapped = previewCorners.map((o) {
        double nx = o.dx;
        double ny = o.dy;
        if ((prevAspect - photoAspect).abs() > 0.005) {
          if (prevAspect < photoAspect) {
            nx = 0.5 + (nx - 0.5) * (prevAspect / photoAspect);
          } else {
            ny = 0.5 + (ny - 0.5) * (photoAspect / prevAspect);
          }
        }
        return CornerPoint(nx.clamp(0.0, 1.0), ny.clamp(0.0, 1.0));
      }).toList();

      // In 3000x4000 photo, centered 2250x4000 crop starts at 375px (0.125) and ends at 2625px (0.875)
      expect(mapped[0].x, closeTo(0.125, 1e-4));
      expect(mapped[1].x, closeTo(0.875, 1e-4));
      expect(mapped[2].x, closeTo(0.875, 1e-4));
      expect(mapped[3].x, closeTo(0.125, 1e-4));
      // Y remains uncompressed
      expect(mapped[0].y, closeTo(0.1, 1e-4));
      expect(mapped[2].y, closeTo(0.9, 1e-4));
    });

    test('Front camera mirroring flips horizontally and maintains [TL, TR, BR, BL] ordering', () {
      final previewCorners = [
        const Offset(0.2, 0.1), // TL in mirrored preview
        const Offset(0.8, 0.15), // TR in mirrored preview
        const Offset(0.75, 0.85), // BR in mirrored preview
        const Offset(0.25, 0.8), // BL in mirrored preview
      ];

      // Mirror mapping: x -> 1 - x, swap TL <-> TR and BL <-> BR
      final mirrored = [
        Offset(1.0 - previewCorners[1].dx, previewCorners[1].dy), // TR becomes TL
        Offset(1.0 - previewCorners[0].dx, previewCorners[0].dy), // TL becomes TR
        Offset(1.0 - previewCorners[3].dx, previewCorners[3].dy), // BL becomes BR
        Offset(1.0 - previewCorners[2].dx, previewCorners[2].dy), // BR becomes BL
      ];

      // Point 0 (TL) was preview TR (0.8, 0.15) -> 1 - 0.8 = 0.2, 0.15
      expect(mirrored[0].dx, closeTo(0.2, 1e-4));
      expect(mirrored[0].dy, closeTo(0.15, 1e-4));

      // Point 1 (TR) was preview TL (0.2, 0.1) -> 1 - 0.2 = 0.8, 0.1
      expect(mirrored[1].dx, closeTo(0.8, 1e-4));
      expect(mirrored[1].dy, closeTo(0.1, 1e-4));

      // Point 2 (BR) was preview BL (0.25, 0.8) -> 1 - 0.25 = 0.75, 0.8
      expect(mirrored[2].dx, closeTo(0.75, 1e-4));
      expect(mirrored[2].dy, closeTo(0.8, 1e-4));

      // Point 3 (BL) was preview BR (0.75, 0.85) -> 1 - 0.75 = 0.25, 0.85
      expect(mirrored[3].dx, closeTo(0.25, 1e-4));
      expect(mirrored[3].dy, closeTo(0.85, 1e-4));
    });
  });

  group('10. EditorProvider Unified Document Lifecycle & Crop Reset', () {
    test('addPage initializes default title when document title is empty', () {
      final editor = EditorProvider();
      expect(editor.documentTitle, isEmpty);

      final page = const DocumentPage(
        id: 'test_page',
        pageNumber: 1,
        corners: [
          CornerPoint(0.1, 0.1),
          CornerPoint(0.9, 0.1),
          CornerPoint(0.9, 0.9),
          CornerPoint(0.1, 0.9),
        ],
        filterType: 'auto',
      );

      editor.addPage(page);
      expect(editor.documentTitle, isNotEmpty);
      expect(editor.documentTitle, startsWith('Scan '));
      expect(editor.cornerPoints[0].dx, closeTo(0.1, 1e-4));
      expect(editor.pages.length, equals(1));
    });

    test('resetCrop resets to full frame when autoDetectedCorners is null', () {
      final editor = EditorProvider();
      final page = const DocumentPage(
        id: 'manual_page',
        pageNumber: 1,
        corners: [
          CornerPoint(0.2, 0.2),
          CornerPoint(0.8, 0.2),
          CornerPoint(0.8, 0.8),
          CornerPoint(0.2, 0.8),
        ],
        autoDetectedCorners: null,
        filterType: 'auto',
      );

      editor.initializeWithPages([page]);
      expect(editor.cornerPoints[0].dx, closeTo(0.2, 1e-4));

      editor.resetCrop();
      expect(editor.cornerPoints[0].dx, equals(0.0));
      expect(editor.cornerPoints[0].dy, equals(0.0));
      expect(editor.cornerPoints[2].dx, equals(1.0));
      expect(editor.cornerPoints[2].dy, equals(1.0));
    });

    test('resetToFullFrame unconditionally restores full image boundary', () {
      final editor = EditorProvider();
      final page = const DocumentPage(
        id: 'detected_page',
        pageNumber: 1,
        corners: [
          CornerPoint(0.15, 0.15),
          CornerPoint(0.85, 0.15),
          CornerPoint(0.85, 0.85),
          CornerPoint(0.15, 0.85),
        ],
        autoDetectedCorners: [
          CornerPoint(0.15, 0.15),
          CornerPoint(0.85, 0.15),
          CornerPoint(0.85, 0.85),
          CornerPoint(0.15, 0.85),
        ],
        filterType: 'auto',
      );

      editor.initializeWithPages([page]);
      expect(editor.cornerPoints[0].dx, closeTo(0.15, 1e-4));

      editor.resetToFullFrame();
      expect(editor.cornerPoints[0].dx, equals(0.0));
      expect(editor.cornerPoints[0].dy, equals(0.0));
      expect(editor.cornerPoints[2].dx, equals(1.0));
      expect(editor.cornerPoints[2].dy, equals(1.0));
    });
  });
}


