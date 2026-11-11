import 'dart:math' as math;
import 'package:image/image.dart' as img;
import '../../models/models.dart';

/// High-performance 4-point perspective transformation (Homography) with bilinear interpolation.
class PerspectiveTransform {
  /// Ensures corners are consistently ordered: Top-Left (0), Top-Right (1), Bottom-Right (2), Bottom-Left (3)
  static List<CornerPoint> sortCorners(List<CornerPoint> points) {
    if (points.length != 4) return points;

    final sortedByY = List<CornerPoint>.from(points)..sort((a, b) => a.y.compareTo(b.y));
    final topTwo = [sortedByY[0], sortedByY[1]]..sort((a, b) => a.x.compareTo(b.x));
    final bottomTwo = [sortedByY[2], sortedByY[3]]..sort((a, b) => a.x.compareTo(b.x));

    final tl = topTwo[0];
    final tr = topTwo[1];
    final br = bottomTwo[1];
    final bl = bottomTwo[0];

    return [tl, tr, br, bl];
  }

  /// Validates whether the 4 points form a non-degenerate, convex quadrilateral
  static bool isValidQuad(List<CornerPoint> corners) {
    if (corners.length != 4) return false;

    for (final p in corners) {
      if (p.x < -0.05 || p.x > 1.05 || p.y < -0.05 || p.y > 1.05) return false;
    }

    bool? sign;
    for (int i = 0; i < 4; i++) {
      final p1 = corners[i];
      final p2 = corners[(i + 1) % 4];
      final p3 = corners[(i + 2) % 4];

      final dx1 = p2.x - p1.x;
      final dy1 = p2.y - p1.y;
      final dx2 = p3.x - p2.x;
      final dy2 = p3.y - p2.y;

      final cross = dx1 * dy2 - dy1 * dx2;
      if (cross.abs() < 1e-5) return false;
      if (sign == null) {
        sign = cross > 0;
      } else if (sign != (cross > 0)) {
        return false;
      }
    }
    return true;
  }

  /// Warps [source] quadrilateral defined by [corners] (TL, TR, BR, BL in normalized 0..1 space)
  /// into a straightened, rectangular document image.
  static img.Image warp({
    required img.Image source,
    required List<CornerPoint> corners,
  }) {
    if (corners.length < 4) return source;
    // Preserve exact four corner correspondence [TL, TR, BR, BL]
    final ordered = corners;

    final srcW = source.width.toDouble();
    final srcH = source.height.toDouble();

    // Denormalize points to source pixel coordinates
    final x0 = ordered[0].x * srcW;
    final y0 = ordered[0].y * srcH;

    final x1 = ordered[1].x * srcW;
    final y1 = ordered[1].y * srcH;

    final x2 = ordered[2].x * srcW;
    final y2 = ordered[2].y * srcH;

    final x3 = ordered[3].x * srcW;
    final y3 = ordered[3].y * srcH;

    // Calculate target output dimensions
    final topW = _hypot(x1 - x0, y1 - y0);
    final botW = _hypot(x2 - x3, y2 - y3);
    final targetW = math.max(topW, botW).round().clamp(64, 4096);

    final leftH = _hypot(x3 - x0, y3 - y0);
    final rightH = _hypot(x2 - x1, y2 - y1);
    final targetH = math.max(leftH, rightH).round().clamp(64, 4096);

    // Compute coefficients for mapping from unit square [0,1]^2 to source quad
    final dx1 = x1 - x2;
    final dx2 = x3 - x2;
    final dx3 = x0 - x1 + x2 - x3;

    final dy1 = y1 - y2;
    final dy2 = y3 - y2;
    final dy3 = y0 - y1 + y2 - y3;

    final det = dx1 * dy2 - dx2 * dy1;

    double a, b, c, d, e, f, g, h;

    if (det.abs() < 1e-7) {
      // Affine fallback
      a = x1 - x0;
      b = x3 - x0;
      c = x0;
      d = y1 - y0;
      e = y3 - y0;
      f = y0;
      g = 0.0;
      h = 0.0;
    } else {
      g = (dx3 * dy2 - dx2 * dy3) / det;
      h = (dx1 * dy3 - dx3 * dy1) / det;
      a = x1 - x0 + g * x1;
      b = x3 - x0 + h * x3;
      c = x0;
      d = y1 - y0 + g * y1;
      e = y3 - y0 + h * y3;
      f = y0;
    }

    final output = img.Image(width: targetW, height: targetH);
    final maxSrcX = source.width - 1;
    final maxSrcY = source.height - 1;

    for (int y = 0; y < targetH; y++) {
      final v = y / targetH;
      for (int x = 0; x < targetW; x++) {
        final u = x / targetW;

        final denom = g * u + h * v + 1.0;
        final sx = (a * u + b * v + c) / denom;
        final sy = (d * u + e * v + f) / denom;

        // Bilinear interpolation
        _setBilinearPixel(source, output, x, y, sx, sy, maxSrcX, maxSrcY);
      }
    }

    return output;
  }

  static double _hypot(double dx, double dy) => math.sqrt(dx * dx + dy * dy);

  /// Bilinear sampling from source image written directly into output
  static void _setBilinearPixel(
    img.Image src,
    img.Image dst,
    int dstX,
    int dstY,
    double x,
    double y,
    int maxX,
    int maxY,
  ) {
    if (x < 0 || y < 0 || x > maxX || y > maxY) {
      final cx = x.clamp(0.0, maxX.toDouble()).round();
      final cy = y.clamp(0.0, maxY.toDouble()).round();
      final p = src.getPixel(cx, cy);
      dst.setPixelRgb(dstX, dstY, p.r.toInt(), p.g.toInt(), p.b.toInt());
      return;
    }

    final x0 = x.floor();
    final y0 = y.floor();
    final x1 = math.min(x0 + 1, maxX);
    final y1 = math.min(y0 + 1, maxY);

    final fx = x - x0;
    final fy = y - y0;

    final p00 = src.getPixel(x0, y0);
    final p10 = src.getPixel(x1, y0);
    final p01 = src.getPixel(x0, y1);
    final p11 = src.getPixel(x1, y1);

    final r = (p00.r * (1 - fx) * (1 - fy) +
               p10.r * fx * (1 - fy) +
               p01.r * (1 - fx) * fy +
               p11.r * fx * fy).round();

    final g = (p00.g * (1 - fx) * (1 - fy) +
               p10.g * fx * (1 - fy) +
               p01.g * (1 - fx) * fy +
               p11.g * fx * fy).round();

    final b = (p00.b * (1 - fx) * (1 - fy) +
               p10.b * fx * (1 - fy) +
               p01.b * (1 - fx) * fy +
               p11.b * fx * fy).round();

    dst.setPixelRgb(dstX, dstY, r, g, b);
  }
}
