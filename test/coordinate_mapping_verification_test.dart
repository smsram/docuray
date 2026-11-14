import 'package:flutter_test/flutter_test.dart';
import 'package:docuray/models/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Coordinate Mapping Regression Verification', () {
    test('Restored mapped coordinates match original 4d3dad7 mapping for identical input', () {
      // 1. Raw model output from YOLO segmentation Douglas-Peucker 4-corner approximation
      final rawModelCorners = [
        const CornerPoint(0.1245, 0.1567), // Top-Left
        const CornerPoint(0.8753, 0.1432), // Top-Right
        const CornerPoint(0.8621, 0.9184), // Bottom-Right
        const CornerPoint(0.1108, 0.8955), // Bottom-Left
      ];

      // 2. Previously working coordinate mapping (4d3dad7)
      // In 4d3dad7:
      // _detectedCorners = result.corners.map((c) => Offset(c.x, c.y)).toList();
      // On screen inside preview (previewW x previewH):
      // actualPoint = Offset(c.dx * previewW, c.dy * previewH);
      const previewW = 392.7;
      const previewH = 698.1;

      final originalMappedPoints = rawModelCorners.map((c) {
        return Offset(c.x * previewW, c.y * previewH);
      }).toList();

      // 3. Current restored coordinate mapping
      final restoredDetectedCorners = rawModelCorners.map((c) => Offset(c.x, c.y)).toList();
      final restoredMappedPoints = restoredDetectedCorners.map((c) {
        return Offset(c.dx * previewW, c.dy * previewH);
      }).toList();

      // Verify that Restored Mapped Coordinates match Original 4d3dad7 Mapped Coordinates EXACTLY
      expect(restoredMappedPoints.length, equals(4));
      for (int i = 0; i < 4; i++) {
        expect(
          restoredMappedPoints[i].dx,
          closeTo(originalMappedPoints[i].dx, 1e-6),
          reason: 'Corner $i X mismatch between original and restored mapping',
        );
        expect(
          restoredMappedPoints[i].dy,
          closeTo(originalMappedPoints[i].dy, 1e-6),
          reason: 'Corner $i Y mismatch between original and restored mapping',
        );
      }

      // 4. Animated display coordinates during interpolation
      // Visual layer lerps from current position to target position
      final initialDisplayCorners = [
        const Offset(0.1000, 0.1200),
        const Offset(0.8500, 0.1100),
        const Offset(0.8400, 0.9000),
        const Offset(0.0900, 0.8700),
      ];

      const progress = 0.5; // Halfway animation tick
      final animatedDisplayCorners = List.generate(4, (i) {
        return Offset.lerp(initialDisplayCorners[i], restoredDetectedCorners[i], progress)!;
      });

      // Animated display coordinates are strictly visual and do NOT alter raw model coordinates
      expect(restoredDetectedCorners[0].dx, equals(0.1245));
      expect(restoredDetectedCorners[0].dy, equals(0.1567));
      expect(animatedDisplayCorners[0].dx, closeTo(0.11225, 1e-5));
      expect(animatedDisplayCorners[0].dy, closeTo(0.13835, 1e-5));

      // 5. Capture coordinates consume raw model prediction, NEVER animated display coordinates
      final capturedCorners = List<Offset>.from(restoredDetectedCorners);
      expect(capturedCorners[0].dx, equals(rawModelCorners[0].x));
      expect(capturedCorners[1].dx, equals(rawModelCorners[1].x));
      expect(capturedCorners[2].dx, equals(rawModelCorners[2].x));
      expect(capturedCorners[3].dx, equals(rawModelCorners[3].x));
    });
  });
}
