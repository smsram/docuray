import 'dart:math' as math;
import 'package:image/image.dart' as img;

/// Real offline document image processing, illumination correction,
/// professional scanner filters, adjustments, and quality detection.
class ImageEnhancer {
  /// Applies the specified filter and adjustments to [source].
  static img.Image process({
    required img.Image source,
    String filterType = 'auto',
    double brightness = 0.0,
    double contrast = 0.0,
    double sharpness = 0.0,
    int rotationDegrees = 0,
  }) {
    var result = img.Image.from(source);

    // 1. Rotation if any
    if (rotationDegrees % 360 != 0) {
      result = img.copyRotate(result, angle: rotationDegrees);
    }

    // 2. Filters
    final normalized = filterType.toLowerCase().trim().replaceAll('-', '_').replaceAll(' ', '_');
    switch (normalized) {
      case 'original':
        // Raw captured colors
        break;

      case 'auto':
      case 'auto_color':
      case 'color':
      case 'magic_color':
        result = _applyAutoColor(result);
        break;

      case 'light_text':
      case 'lighttext':
        result = _applyLightText(result);
        break;

      case 'grayscale':
      case 'gray':
        result = _applyGrayscale(result);
        break;

      case 'whiteboard':
        result = _applyWhiteboard(result);
        break;

      case 'bw':
      case 'black_and_white':
        result = _applySauvolaBlackAndWhite(result);
        break;

      default:
        result = _applyAutoColor(result);
        break;
    }

    // 3. Manual Adjustments
    if (brightness != 0.0 || contrast != 0.0) {
      result = _applyBrightnessContrast(result, brightness, contrast);
    }

    if (sharpness > 0.05) {
      result = _applyHaloFreeSharpen(result, sharpness);
    }

    return result;
  }

  /// AUTO-COLOR:
  /// - Estimates uneven background illumination.
  /// - Normalizes paper shadows.
  /// - Ink protection: preserves colored handwriting, highlighters, stamps, and diagrams.
  static img.Image _applyAutoColor(img.Image src) {
    final w = src.width;
    final h = src.height;
    final illum = _estimateIllumination(src);
    final out = img.Image(width: w, height: h);

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = src.getPixel(x, y);
        final bg = illum[y * w + x].clamp(20.0, 255.0);
        final scale = (248.0 / bg).clamp(0.7, 1.8);

        final nr = (p.r * scale).clamp(0.0, 255.0);
        final ng = (p.g * scale).clamp(0.0, 255.0);
        final nb = (p.b * scale).clamp(0.0, 255.0);

        // Saturation / chroma check for ink protection
        final maxC = math.max(p.r, math.max(p.g, p.b)).toDouble();
        final minC = math.min(p.r, math.min(p.g, p.b)).toDouble();
        final chroma = maxC - minC;

        int fr, fg, fb;
        if (chroma > 22.0) {
          // Colored stroke (pen, stamp, diagram, highlighter) -> preserve vivid hue
          final t = ((chroma - 22.0) / 35.0).clamp(0.0, 0.85);
          fr = ((1.0 - t) * nr + t * p.r).round().clamp(0, 255);
          fg = ((1.0 - t) * ng + t * p.g).round().clamp(0, 255);
          fb = ((1.0 - t) * nb + t * p.b).round().clamp(0, 255);
        } else {
          // Neutral paper / dark text -> apply mild contrast curve for crisp dark strokes
          final lum = 0.299 * nr + 0.587 * ng + 0.114 * nb;
          if (lum > 230.0) {
            fr = math.min(255, (nr * 1.02).round());
            fg = math.min(255, (ng * 1.02).round());
            fb = math.min(255, (nb * 1.02).round());
          } else {
            fr = (255.0 * math.pow(nr / 255.0, 1.08)).round().clamp(0, 255);
            fg = (255.0 * math.pow(ng / 255.0, 1.08)).round().clamp(0, 255);
            fb = (255.0 * math.pow(nb / 255.0, 1.08)).round().clamp(0, 255);
          }
        }

        out.setPixelRgb(x, y, fr, fg, fb);
      }
    }

    return out;
  }

  /// LIGHT TEXT:
  /// - Brightens document background and normalizes uneven lighting.
  /// - Controlled tonal stretching specifically enhances faint handwriting, pencil marks,
  ///   and pale thermal receipts without erasing thin strokes.
  static img.Image _applyLightText(img.Image src) {
    final w = src.width;
    final h = src.height;
    final illum = _estimateIllumination(src);
    final out = img.Image(width: w, height: h);

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = src.getPixel(x, y);
        final bg = illum[y * w + x].clamp(20.0, 255.0);
        final scale = (252.0 / bg).clamp(0.8, 2.0);

        var nr = (p.r * scale).clamp(0.0, 255.0);
        var ng = (p.g * scale).clamp(0.0, 255.0);
        var nb = (p.b * scale).clamp(0.0, 255.0);

        final lum = 0.299 * nr + 0.587 * ng + 0.114 * nb;

        if (lum > 228.0) {
          // Paper region smoothly normalized to white
          nr = 255.0;
          ng = 255.0;
          nb = 255.0;
        } else {
          // Faint text stretched downwards for dark, readable strokes
          final norm = (lum / 228.0).clamp(0.0, 1.0);
          final stretch = math.pow(norm, 1.6) * 190.0;
          final ratio = stretch / math.max(1.0, lum);
          nr = (nr * ratio).clamp(0.0, 255.0);
          ng = (ng * ratio).clamp(0.0, 255.0);
          nb = (nb * ratio).clamp(0.0, 255.0);
        }

        out.setPixelRgb(x, y, nr.round(), ng.round(), nb.round());
      }
    }

    return out;
  }

  /// GRAYSCALE:
  /// - Rec. 601 perceptual luminance: 0.299R + 0.587G + 0.114B.
  /// - Dynamic range histogram stretching to maximize readability without clipping.
  static img.Image _applyGrayscale(img.Image src) {
    final w = src.width;
    final h = src.height;
    final lums = List<int>.filled(w * h, 0);

    int minLum = 255;
    int maxLum = 0;

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = src.getPixel(x, y);
        final lum = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round().clamp(0, 255);
        final idx = y * w + x;
        lums[idx] = lum;
        if (lum < minLum) minLum = lum;
        if (lum > maxLum) maxLum = lum;
      }
    }

    final range = math.max(1, maxLum - minLum);
    final out = img.Image(width: w, height: h);

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final lum = lums[y * w + x];
        final norm = (lum - minLum) / range;
        final curved = (math.pow(norm, 0.95) * 255.0).round().clamp(0, 255);
        out.setPixelRgb(x, y, curved, curved, curved);
      }
    }

    return out;
  }

  /// WHITEBOARD:
  /// - Reduces room shadows, reflections, and vignetting across whiteboard surfaces.
  /// - Boosts saturation for colored marker annotations (Red, Blue, Green).
  /// - Deepens black marker strokes and whitens the background board.
  static img.Image _applyWhiteboard(img.Image src) {
    final w = src.width;
    final h = src.height;
    final illum = _estimateIllumination(src);
    final out = img.Image(width: w, height: h);

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = src.getPixel(x, y);
        final bg = illum[y * w + x].clamp(20.0, 255.0);
        final scale = (252.0 / bg).clamp(0.8, 2.2);

        var nr = (p.r * scale).clamp(0.0, 255.0);
        var ng = (p.g * scale).clamp(0.0, 255.0);
        var nb = (p.b * scale).clamp(0.0, 255.0);

        final isRedMarker = p.r > p.g + 16 && p.r > p.b + 16;
        final isBlueMarker = p.b > p.r + 14 && p.b > p.g + 14;
        final isGreenMarker = p.g > p.r + 14 && p.g > p.b + 14;

        if (isRedMarker) {
          nr = math.min(255.0, nr * 1.15);
          ng = (ng * 0.75).clamp(0.0, 255.0);
          nb = (nb * 0.75).clamp(0.0, 255.0);
        } else if (isBlueMarker) {
          nb = math.min(255.0, nb * 1.18);
          nr = (nr * 0.70).clamp(0.0, 255.0);
          ng = (ng * 0.85).clamp(0.0, 255.0);
        } else if (isGreenMarker) {
          ng = math.min(255.0, ng * 1.15);
          nr = (nr * 0.70).clamp(0.0, 255.0);
          nb = (nb * 0.70).clamp(0.0, 255.0);
        } else {
          final lum = 0.299 * nr + 0.587 * ng + 0.114 * nb;
          if (lum > 220.0) {
            nr = 255.0;
            ng = 255.0;
            nb = 255.0;
          } else {
            final dark = math.pow(lum / 220.0, 1.4) * 220.0;
            nr = dark;
            ng = dark;
            nb = dark;
          }
        }

        out.setPixelRgb(x, y, nr.round(), ng.round(), nb.round());
      }
    }

    return out;
  }

  /// BLACK & WHITE (Sauvola Adaptive Thresholding):
  /// - Gold standard document binarization.
  /// - Adaptive window size scaled to image resolution.
  /// - T = m * (1 + k * (s / 128 - 1)).
  /// - Preserves fine handwriting and completely prevents dark shadow patches.
  static img.Image _applySauvolaBlackAndWhite(img.Image src) {
    final w = src.width;
    final h = src.height;
    final gray = List<double>.filled(w * h, 0.0);

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = src.getPixel(x, y);
        gray[y * w + x] = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
      }
    }

    final radius = math.max(12, math.min(w, h) ~/ 36);
    final mean = _boxFilter(gray, w, h, radius);
    final graySq = List<double>.generate(w * h, (i) => gray[i] * gray[i]);
    final meanSq = _boxFilter(graySq, w, h, radius);

    final out = img.Image(width: w, height: h);
    const k = 0.20;
    const rDynamic = 128.0;

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final idx = y * w + x;
        final m = mean[idx];
        final variance = math.max(0.0, meanSq[idx] - m * m);
        final s = math.sqrt(variance);

        final t = m * (1.0 + k * (s / rDynamic - 1.0));
        final bw = gray[idx] < t ? 0 : 255;
        out.setPixelRgb(x, y, bw, bw, bw);
      }
    }

    return out;
  }

  /// Resolution-aware background illumination map estimation
  static List<double> _estimateIllumination(img.Image src) {
    final w = src.width;
    final h = src.height;
    final gridW = 120;
    final gridH = math.max(1, (120.0 * h / w).round());

    final smallLum = List<double>.filled(gridW * gridH, 0.0);
    final xStep = w / gridW;
    final yStep = h / gridH;

    for (int gy = 0; gy < gridH; gy++) {
      final sy = (gy * yStep).toInt().clamp(0, h - 1);
      for (int gx = 0; gx < gridW; gx++) {
        final sx = (gx * xStep).toInt().clamp(0, w - 1);
        final p = src.getPixel(sx, sy);
        smallLum[gy * gridW + gx] = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
      }
    }

    final blurredSmall = _boxFilter(smallLum, gridW, gridH, 14);

    final outMap = List<double>.filled(w * h, 0.0);
    for (int y = 0; y < h; y++) {
      final gy = (y / math.max(1, h - 1)) * (gridH - 1);
      final y0 = gy.toInt().clamp(0, gridH - 1);
      final y1 = math.min(y0 + 1, gridH - 1);
      final fy = gy - y0;

      for (int x = 0; x < w; x++) {
        final gx = (x / math.max(1, w - 1)) * (gridW - 1);
        final x0 = gx.toInt().clamp(0, gridW - 1);
        final x1 = math.min(x0 + 1, gridW - 1);
        final fx = gx - x0;

        final v00 = blurredSmall[y0 * gridW + x0];
        final v10 = blurredSmall[y0 * gridW + x1];
        final v01 = blurredSmall[y1 * gridW + x0];
        final v11 = blurredSmall[y1 * gridW + x1];

        outMap[y * w + x] = v00 * (1.0 - fx) * (1.0 - fy) +
            v10 * fx * (1.0 - fy) +
            v01 * (1.0 - fx) * fy +
            v11 * fx * fy;
      }
    }

    return outMap;
  }

  /// Fast separable box filter O(1) per pixel
  static List<double> _boxFilter(List<double> src, int w, int h, int r) {
    final temp = List<double>.filled(w * h, 0.0);
    final out = List<double>.filled(w * h, 0.0);
    final div = 2 * r + 1;

    for (int y = 0; y < h; y++) {
      final rowOffset = y * w;
      double sum = 0.0;
      for (int k = -r; k <= r; k++) {
        sum += src[rowOffset + k.clamp(0, w - 1)];
      }
      temp[rowOffset] = sum / div;

      for (int x = 1; x < w; x++) {
        final addIdx = (x + r).clamp(0, w - 1);
        final subIdx = (x - r - 1).clamp(0, w - 1);
        sum += src[rowOffset + addIdx] - src[rowOffset + subIdx];
        temp[rowOffset + x] = sum / div;
      }
    }

    for (int x = 0; x < w; x++) {
      double sum = 0.0;
      for (int k = -r; k <= r; k++) {
        final yIdx = k.clamp(0, h - 1);
        sum += temp[yIdx * w + x];
      }
      out[x] = sum / div;

      for (int y = 1; y < h; y++) {
        final addIdx = (y + r).clamp(0, h - 1);
        final subIdx = (y - r - 1).clamp(0, h - 1);
        sum += temp[addIdx * w + x] - temp[subIdx * w + x];
        out[y * w + x] = sum / div;
      }
    }

    return out;
  }

  /// Brightness and Contrast adjustments
  static img.Image _applyBrightnessContrast(img.Image src, double brightness, double contrast) {
    final bOffset = brightness * 128.0;
    final cFactor = math.max(0.0, (contrast + 1.0) / 1.0);

    final out = img.Image(width: src.width, height: src.height);
    for (int y = 0; y < src.height; y++) {
      for (int x = 0; x < src.width; x++) {
        final p = src.getPixel(x, y);
        var r = p.r.toDouble();
        var g = p.g.toDouble();
        var b = p.b.toDouble();

        if (brightness != 0.0) {
          r += bOffset;
          g += bOffset;
          b += bOffset;
        }
        if (contrast != 0.0) {
          r = (r - 128.0) * cFactor + 128.0;
          g = (g - 128.0) * cFactor + 128.0;
          b = (b - 128.0) * cFactor + 128.0;
        }

        out.setPixelRgb(
          x,
          y,
          r.round().clamp(0, 255),
          g.round().clamp(0, 255),
          b.round().clamp(0, 255),
        );
      }
    }

    return out;
  }

  /// Halo-free unsharp mask sharpening with noise thresholding
  static img.Image _applyHaloFreeSharpen(img.Image src, double sharpness) {
    final w = src.width;
    final h = src.height;
    final amount = sharpness.clamp(0.0, 1.0) * 1.5;
    final out = img.Image(width: w, height: h);

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = src.getPixel(x, y);
        if (x == 0 || y == 0 || x == w - 1 || y == h - 1) {
          out.setPixel(x, y, p);
          continue;
        }

        final pU = src.getPixel(x, y - 1);
        final pD = src.getPixel(x, y + 1);
        final pL = src.getPixel(x - 1, y);
        final pR = src.getPixel(x + 1, y);

        final rBlur = (p.r * 2 + pU.r + pD.r + pL.r + pR.r) / 6.0;
        final gBlur = (p.g * 2 + pU.g + pD.g + pL.g + pR.g) / 6.0;
        final bBlur = (p.b * 2 + pU.b + pD.b + pL.b + pR.b) / 6.0;

        final rDiff = p.r - rBlur;
        final gDiff = p.g - gBlur;
        final bDiff = p.b - bBlur;

        final rBoost = rDiff.abs() > 3.0 ? (rDiff * amount).clamp(-28.0, 28.0) : 0.0;
        final gBoost = gDiff.abs() > 3.0 ? (gDiff * amount).clamp(-28.0, 28.0) : 0.0;
        final bBoost = bDiff.abs() > 3.0 ? (bDiff * amount).clamp(-28.0, 28.0) : 0.0;

        out.setPixelRgb(
          x,
          y,
          (p.r + rBoost).round().clamp(0, 255),
          (p.g + gBoost).round().clamp(0, 255),
          (p.b + bBoost).round().clamp(0, 255),
        );
      }
    }

    return out;
  }

  /// Lightweight sharpness metric (Laplacian variance proxy)
  /// Returns a sharpness score (higher is sharper, > 25 is acceptable for auto capture)
  static double estimateSharpness(img.Image src) {
    final sample = img.copyResize(src, width: 256, height: 256);
    double sumGrad = 0;
    int count = 0;

    for (int y = 1; y < 255; y++) {
      for (int x = 1; x < 255; x++) {
        final p = sample.getPixel(x, y);
        final pRight = sample.getPixel(x + 1, y);
        final pDown = sample.getPixel(x, y + 1);

        final lum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
        final lumRight = 0.299 * pRight.r + 0.587 * pRight.g + 0.114 * pRight.b;
        final lumDown = 0.299 * pDown.r + 0.587 * pDown.g + 0.114 * pDown.b;

        final gx = lumRight - lum;
        final gy = lumDown - lum;
        sumGrad += math.sqrt(gx * gx + gy * gy);
        count++;
      }
    }

    return count > 0 ? (sumGrad / count) : 0.0;
  }

  /// Average brightness in range [0..255]
  static double estimateBrightness(img.Image src) {
    final sample = img.copyResize(src, width: 128, height: 128);
    double sumLum = 0;
    int count = 0;

    for (int y = 0; y < sample.height; y++) {
      for (int x = 0; x < sample.width; x++) {
        final p = sample.getPixel(x, y);
        sumLum += 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
        count++;
      }
    }

    return count > 0 ? (sumLum / count) : 128.0;
  }
}
