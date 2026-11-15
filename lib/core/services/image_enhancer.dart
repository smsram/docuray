import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Shared intermediate preprocessing data matching the Python OpenCV pipeline:
/// - [normL]: Normalized L-channel (0..255) after 2-stage illumination and micro-crease flattening
/// - [fineStrokeSignal]: Sharpness-gated fine stroke detector signal (float32)
/// - [aClean]: Paper-color-cast neutralized A-channel (float32, centered at 0)
/// - [bClean]: Paper-color-cast neutralized B-channel (float32, centered at 0)
class PreprocessedDocument {
  final int width;
  final int height;
  final Uint8List normL;
  final Float32List fineStrokeSignal;
  final Float32List aClean;
  final Float32List bClean;

  const PreprocessedDocument({
    required this.width,
    required this.height,
    required this.normL,
    required this.fineStrokeSignal,
    required this.aClean,
    required this.bClean,
  });
}

/// Offline document enhancement engine reproducing the Python OpenCV reference pipeline:
/// Two-stage crease-free illumination estimator, micro-crease flattener,
/// sharpness-gated stroke detection, paper color cast neutralization,
/// and the 5 Adobe Scan filter presets.
class ImageEnhancer {
  static PreprocessedDocument? _cachedPreproc;
  static int? _cachedPreprocSourceHash;

  static void clearPreprocCache() {
    _cachedPreproc = null;
    _cachedPreprocSourceHash = null;
  }

  static Uint8List getCleanBackground(Uint8List channel, int width, int height) {
    return getCreaseFreeIllumination(channel, width, height);
  }

  static Uint8List buildLevelsLut(int blackPt, int whitePt, double gamma) {
    final lut = Uint8List(256);
    final range = math.max(1.0, (whitePt - blackPt).toDouble());
    final invGamma = 1.0 / gamma;
    for (int i = 0; i < 256; i++) {
      var norm = ((i - blackPt) / range).clamp(0.0, 1.0);
      if (gamma != 1.0) {
        final ink = math.pow(1.0 - norm, invGamma).toDouble();
        norm = 1.0 - ink;
      }
      lut[i] = (norm * 255.0).round().clamp(0, 255);
    }
    return lut;
  }

  /// Variance of Laplacian for image sharpness / blur detection.
  static double estimateSharpness(img.Image image) {
    final w = image.width;
    final h = image.height;
    if (w < 3 || h < 3) return 0.0;

    double sum = 0.0;
    double sumSq = 0.0;
    int count = 0;

    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final p = image.getPixel(x, y);
        final pU = image.getPixel(x, y - 1);
        final pD = image.getPixel(x, y + 1);
        final pL = image.getPixel(x - 1, y);
        final pR = image.getPixel(x + 1, y);

        final lum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
        final lumU = 0.299 * pU.r + 0.587 * pU.g + 0.114 * pU.b;
        final lumD = 0.299 * pD.r + 0.587 * pD.g + 0.114 * pD.b;
        final lumL = 0.299 * pL.r + 0.587 * pL.g + 0.114 * pL.b;
        final lumR = 0.299 * pR.r + 0.587 * pR.g + 0.114 * pR.b;

        final lap = (lumU + lumD + lumL + lumR - 4.0 * lum).abs();
        sum += lap;
        sumSq += lap * lap;
        count++;
      }
    }

    if (count == 0) return 0.0;
    final mean = sum / count;
    return math.sqrt(math.max(0.0, (sumSq / count) - (mean * mean)));
  }

  /// Mean luminance (0..255) for brightness detection.
  static double estimateBrightness(img.Image image) {
    if (image.width == 0 || image.height == 0) return 0.0;
    double sum = 0.0;
    for (final p in image) {
      sum += 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
    }
    return sum / (image.width * image.height);
  }

  // ---------------------------------------------------------------------------
  // Precomputed tables for performance
  // ---------------------------------------------------------------------------
  static final Float64List _srgbToLinearTable = _buildSrgbToLinearTable();

  static Float64List _buildSrgbToLinearTable() {
    final table = Float64List(256);
    for (int i = 0; i < 256; i++) {
      final c = i / 255.0;
      table[i] = c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    }
    return table;
  }

  static double _linearToSrgb(double c) {
    if (c <= 0.0) return 0.0;
    if (c >= 1.0) return 1.0;
    return c <= 0.0031308 ? c * 12.92 : 1.055 * math.pow(c, 1.0 / 2.4) - 0.055;
  }

  // ---------------------------------------------------------------------------
  // Main Entry Point
  // ---------------------------------------------------------------------------

  /// Applies the specified filter and manual adjustments to [source].
  /// Uses cached [PreprocessedDocument] if available for the same image.
  static img.Image process({
    required img.Image source,
    String filterType = 'auto',
    double brightness = 0.0,
    double contrast = 0.0,
    double sharpness = 0.0,
    double highlights = 0.0,
    double shadows = 0.0,
    double exposure = 0.0,
    double saturation = 0.0,
    int rotationDegrees = 0,
    PreprocessedDocument? precomputed,
  }) {
    var result = source;

    if (rotationDegrees % 360 != 0) {
      result = img.copyRotate(result, angle: rotationDegrees);
    }

    final normalized = filterType.toLowerCase().trim().replaceAll('-', '_').replaceAll(' ', '_');

    if (normalized == 'original') {
      result = _applyAdjustments(
        result,
        brightness: brightness,
        contrast: contrast,
        highlights: highlights,
        shadows: shadows,
        exposure: exposure,
        saturation: saturation,
      );
      if (sharpness > 0.05) {
        result = _applyHaloFreeSharpen(result, sharpness);
      }
      return result;
    }

    final preproc = precomputed ?? getOrComputePreproc(result);

    switch (normalized) {
      case 'auto':
      case 'auto_color':
      case 'color':
      case 'magic_color':
        result = filterAutoColor(preproc);
        break;

      case 'light_text':
      case 'lighttext':
        result = filterLightText(preproc);
        break;

      case 'grayscale':
      case 'gray':
        result = filterGrayscale(preproc);
        break;

      case 'whiteboard':
        result = filterWhiteboard(preproc);
        break;

      case 'bw':
      case 'black_and_white':
        result = filterBlackAndWhite(preproc);
        break;

      default:
        result = filterAutoColor(preproc);
        break;
    }

    result = _applyAdjustments(
      result,
      brightness: brightness,
      contrast: contrast,
      highlights: highlights,
      shadows: shadows,
      exposure: exposure,
      saturation: saturation,
    );

    if (sharpness > 0.05) {
      result = _applyHaloFreeSharpen(result, sharpness);
    }

    return result;
  }

  static PreprocessedDocument getOrComputePreproc(img.Image source) {
    final srcHash = Object.hash(source.width, source.height, source.length);
    if (_cachedPreproc != null && _cachedPreprocSourceHash == srcHash) {
      return _cachedPreproc!;
    }
    final computed = preprocessDocument(source);
    _cachedPreproc = computed;
    _cachedPreprocSourceHash = srcHash;
    return computed;
  }

  // ---------------------------------------------------------------------------
  // Shared Preprocessing Pipeline
  // ---------------------------------------------------------------------------

  /// Two-stage Morphological Illumination Estimator matching Python reference:
  /// 1. Inpaints ultra-dark solid blocks (e.g. navy banner) using Telea FMM inpainting.
  /// 2. Uses 17x17 closing filter to bridge over handwriting and pencil lines while
  ///    closely hugging sharp paper creases and notebook spine shadows.
  static Uint8List getCreaseFreeIllumination(Uint8List lChannel, int w, int h) {
    final scale = 800.0 / math.max(h, w);
    final sh = math.max(100, (h * scale).toInt());
    final sw = math.max(100, (w * scale).toInt());

    final small = _resizeArea(lChannel, w, h, sw, sh);

    // Stage 1: Protect only large dark solid banners
    var kCoarse = math.max(35, (math.min(sh, sw) * 0.22).toInt() | 1);
    if (kCoarse % 2 == 0) kCoarse += 1;

    final coarseBg = _morphologyCloseEllipse(small, sw, sh, kCoarse);

    final nSmall = sw * sh;
    final bannerMask = Uint8List(nSmall);
    bool hasBanner = false;
    for (int i = 0; i < nSmall; i++) {
      final s = small[i];
      final c = coarseBg[i];
      if ((c - s > 55) && (s < 115)) {
        bannerMask[i] = 255;
        hasBanner = true;
      }
    }

    Uint8List paperNoBanners;
    if (hasBanner) {
      final dilatedMask = _dilateEllipse(bannerMask, sw, sh, 9);
      paperNoBanners = _inpaintTelea(small, dilatedMask, sw, sh, radius: 7);
    } else {
      paperNoBanners = small;
    }

    // Stage 2: Follow paper folds and spine shadows while bridging over text/pencil
    final fineBg = _morphologyCloseEllipse(paperNoBanners, sw, sh, 17);
    final blurredFine = _gaussianBlurUint8(fineBg, sw, sh, 21, 0.0);

    final illumFull = _resizeBicubic(blurredFine, sw, sh, w, h);
    for (int i = 0; i < illumFull.length; i++) {
      if (illumFull[i] < 20) illumFull[i] = 20;
    }

    return illumFull;
  }

  /// Extracts shared normalized lightness, sharpness-gated fine stroke detector,
  /// and paper-cast neutralized chrominance channels.
  static PreprocessedDocument preprocessDocument(img.Image imgSource) {
    final w = imgSource.width;
    final h = imgSource.height;
    final n = w * h;

    final rgb = imgSource.getBytes(order: img.ChannelOrder.rgb);
    final l = Uint8List(n);
    final a = Uint8List(n);
    final b = Uint8List(n);
    _rgbToLab(rgb, l, a, b);

    // 1. Primary illumination normalization
    final illumL = getCreaseFreeIllumination(l, w, h);
    final normL = Uint8List(n);
    for (int i = 0; i < n; i++) {
      normL[i] = ((l[i] * 255.0) / illumL[i]).round().clamp(0, 255);
    }

    // 2. Micro-crease flattener for sharp paper folds
    final scale = 800.0 / math.max(h, w);
    final sh = math.max(10, (h * scale).toInt());
    final sw = math.max(10, (w * scale).toInt());
    final normSmall = _resizeArea(normL, w, h, sw, sh);

    final paperEst = Uint8List(sw * sh);
    for (int i = 0; i < sw * sh; i++) {
      final v = normSmall[i];
      paperEst[i] = v < 165 ? 255 : v;
    }

    final resBgSmall = _morphologyCloseEllipse(paperEst, sw, sh, 13);
    final resBgBlurred = _gaussianBlurUint8(resBgSmall, sw, sh, 15, 0.0);
    final resBgFull = _resizeBicubic(resBgBlurred, sw, sh, w, h);

    for (int i = 0; i < n; i++) {
      final bg = math.max(180, resBgFull[i]);
      normL[i] = ((normL[i] * 255.0) / bg).round().clamp(0, 255);
    }

    // 3. Sharpness-Gated Fine Stroke Detector
    final lFloat = Float32List(n);
    for (int i = 0; i < n; i++) {
      lFloat[i] = normL[i].toDouble();
    }

    final gFine = _gaussianBlurFloat(lFloat, w, h, 0, 0.7);
    final gSurround = _gaussianBlurFloat(lFloat, w, h, 0, 3.6);

    final rawDog = Float32List(n);
    for (int i = 0; i < n; i++) {
      final diff = gSurround[i] - gFine[i] - 2.4;
      rawDog[i] = diff > 0.0 ? diff : 0.0;
    }

    // Measure local edge sharpness via Sobel gradient magnitude on gFine
    final gx = Float32List(n);
    final gy = Float32List(n);
    _sobel3x3(gFine, w, h, gx, gy);

    final gradMagRaw = Float32List(n);
    for (int i = 0; i < n; i++) {
      gradMagRaw[i] = math.sqrt(gx[i] * gx[i] + gy[i] * gy[i]);
    }
    final gradMag = _gaussianBlurFloat(gradMagRaw, w, h, 5, 0.0);

    final fineStrokeSignal = Float32List(n);
    for (int i = 0; i < n; i++) {
      final gate = ((gradMag[i] - 6.0) / 14.0).clamp(0.0, 1.0);
      fineStrokeSignal[i] = rawDog[i] * gate;
    }

    // 4. Neutralize warm/yellow paper color cast in A & B channels
    final aFloat = Float32List(n);
    final bFloat = Float32List(n);
    for (int i = 0; i < n; i++) {
      aFloat[i] = (a[i] - 128.0);
      bFloat[i] = (b[i] - 128.0);
    }

    final aBg = _gaussianBlurFloat(aFloat, w, h, 61, 0.0);
    final bBg = _gaussianBlurFloat(bFloat, w, h, 61, 0.0);

    final aClean = Float32List(n);
    final bClean = Float32List(n);
    for (int i = 0; i < n; i++) {
      aClean[i] = aFloat[i] - aBg[i] * 0.92;
      bClean[i] = bFloat[i] - bBg[i] * 0.92;
    }

    return PreprocessedDocument(
      width: w,
      height: h,
      normL: normL,
      fineStrokeSignal: fineStrokeSignal,
      aClean: aClean,
      bClean: bClean,
    );
  }

  /// Maps normalized lightness and sharpness-gated pencil/ink signal to target tonal range.
  static Uint8List renderTonedLightness(
    Uint8List normL,
    Float32List fineStrokeSignal, {
    required double blackPt,
    required double whitePt,
    required double gamma,
    required double strokeGain,
    double minL = 0.0,
    double maxL = 255.0,
  }) {
    final n = normL.length;
    final out = Uint8List(n);
    final range = math.max(1.0, whitePt - blackPt);
    final invGamma = gamma != 1.0 ? 1.0 / gamma : 1.0;
    final lRange = maxL - minL;

    for (int i = 0; i < n; i++) {
      final nl = normL[i].toDouble();
      final sig = fineStrokeSignal[i].toDouble();
      final enhancedL = (nl - sig * strokeGain).clamp(0.0, 255.0);
      var scaled = ((enhancedL - blackPt) / range).clamp(0.0, 1.0);
      if (gamma != 1.0) {
        final ink = math.pow(1.0 - scaled, invGamma).toDouble();
        scaled = 1.0 - ink;
      }
      out[i] = (minL + scaled * lRange).round().clamp(0, 255);
    }
    return out;
  }

  /// Restores and amplifies ink colors while keeping the white paper background completely neutral.
  static img.Image combineColorChannels(
    Uint8List cleanL,
    Float32List aClean,
    Float32List bClean,
    int width,
    int height, {
    double chromaBoost = 2.0,
    bool liftDarkInk = false,
  }) {
    final n = width * height;
    final outL = Uint8List(n);
    final outA = Uint8List(n);
    final outB = Uint8List(n);

    for (int i = 0; i < n; i++) {
      final lVal = cleanL[i].toDouble();
      final af = aClean[i].toDouble();
      final bf = bClean[i].toDouble();
      final chromaMag = math.sqrt(af * af + bf * bf);

      final darknessMask = ((244.0 - lVal) / 26.0).clamp(0.0, 1.0);
      final colorMask = ((chromaMag - 2.5) / 8.0).clamp(0.0, 1.0);
      final inkWeight = math.max(darknessMask, colorMask);

      var finalL = lVal;
      if (liftDarkInk) {
        final colorInkZone = ((chromaMag - 3.0) / 8.0).clamp(0.0, 1.0) * (lVal < 90.0 ? 1.0 : 0.0);
        finalL = (lVal + colorInkZone * 22.0).clamp(0.0, 255.0);
      }

      final aVal = (128.0 + af * inkWeight * chromaBoost).round().clamp(0, 255);
      final bVal = (128.0 + bf * inkWeight * chromaBoost).round().clamp(0, 255);

      outL[i] = finalL.round().clamp(0, 255);
      outA[i] = aVal;
      outB[i] = bVal;
    }

    final rgb = Uint8List(n * 3);
    _labToRgb(outL, outA, outB, rgb);

    return img.Image.fromBytes(
      width: width,
      height: height,
      bytes: rgb.buffer,
      order: img.ChannelOrder.rgb,
      numChannels: 3,
    );
  }

  /// Standard Gaussian unsharp mask sharpening.
  static img.Image unsharpMask(img.Image image, {double sigma = 0.9, double strength = 0.6}) {
    final w = image.width;
    final h = image.height;
    final n = w * h;

    final rgb = image.getBytes(order: img.ChannelOrder.rgb);
    final r = Uint8List(n);
    final g = Uint8List(n);
    final b = Uint8List(n);
    for (int i = 0; i < n; i++) {
      r[i] = rgb[i * 3];
      g[i] = rgb[i * 3 + 1];
      b[i] = rgb[i * 3 + 2];
    }

    final ksize = (sigma * 3).round() * 2 + 1;
    final blurR = _gaussianBlurUint8(r, w, h, ksize, sigma);
    final blurG = _gaussianBlurUint8(g, w, h, ksize, sigma);
    final blurB = _gaussianBlurUint8(b, w, h, ksize, sigma);

    final outRgb = Uint8List(n * 3);
    final wOrig = 1.0 + strength;
    final wBlur = -strength;

    for (int i = 0; i < n; i++) {
      outRgb[i * 3] = (r[i] * wOrig + blurR[i] * wBlur).round().clamp(0, 255);
      outRgb[i * 3 + 1] = (g[i] * wOrig + blurG[i] * wBlur).round().clamp(0, 255);
      outRgb[i * 3 + 2] = (b[i] * wOrig + blurB[i] * wBlur).round().clamp(0, 255);
    }

    return img.Image.fromBytes(
      width: w,
      height: h,
      bytes: outRgb.buffer,
      order: img.ChannelOrder.rgb,
      numChannels: 3,
    );
  }

  static Uint8List _unsharpMaskGray(Uint8List gray, int w, int h, {double sigma = 1.0, double strength = 0.4}) {
    final n = w * h;
    final ksize = (sigma * 3).round() * 2 + 1;
    final blur = _gaussianBlurUint8(gray, w, h, ksize, sigma);
    final out = Uint8List(n);
    final wOrig = 1.0 + strength;
    final wBlur = -strength;
    for (int i = 0; i < n; i++) {
      out[i] = (gray[i] * wOrig + blur[i] * wBlur).round().clamp(0, 255);
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // 5 Adobe Scan Filter Presets
  // ---------------------------------------------------------------------------

  /// 1. Auto-Color: Crisp #FFFFFF white paper with natural blue ballpoint ink recovery,
  /// vivid purple stamps, and clean pencil diagrams.
  static img.Image filterAutoColor(PreprocessedDocument preproc) {
    final cleanL = renderTonedLightness(
      preproc.normL,
      preproc.fineStrokeSignal,
      blackPt: 20,
      whitePt: 236,
      gamma: 1.30,
      strokeGain: 1.5,
    );
    final combined = combineColorChannels(
      cleanL,
      preproc.aClean,
      preproc.bClean,
      preproc.width,
      preproc.height,
      chromaBoost: 2.1,
      liftDarkInk: true,
    );
    return unsharpMask(combined, sigma: 0.9, strength: 0.55);
  }

  /// 2. Light Text: Bold, darkened strokes for faint pencil boxes and washed-out ink,
  /// with sharpness gating so reverse-side bleed-through is NOT amplified.
  static img.Image filterLightText(PreprocessedDocument preproc) {
    final w = preproc.width;
    final h = preproc.height;
    final n = w * h;

    final cleanL = renderTonedLightness(
      preproc.normL,
      preproc.fineStrokeSignal,
      blackPt: 32,
      whitePt: 233,
      gamma: 1.90,
      strokeGain: 2.8,
    );

    final erodedL = _erode2x2Ellipse(cleanL, w, h);
    final boldL = Uint8List(n);
    for (int i = 0; i < n; i++) {
      boldL[i] = (cleanL[i] * 0.30 + erodedL[i] * 0.70).round().clamp(0, 255);
    }

    final combined = combineColorChannels(
      boldL,
      preproc.aClean,
      preproc.bClean,
      w,
      h,
      chromaBoost: 2.4,
      liftDarkInk: true,
    );
    return unsharpMask(combined, sigma: 0.8, strength: 0.80);
  }

  /// 3. Grayscale: True Photocopy/Scanner Grayscale with soft gray paper ceiling (245)
  /// and charcoal-gray ink (38).
  static img.Image filterGrayscale(PreprocessedDocument preproc) {
    final w = preproc.width;
    final h = preproc.height;

    final grayL = renderTonedLightness(
      preproc.normL,
      preproc.fineStrokeSignal,
      blackPt: 10,
      whitePt: 244,
      gamma: 1.12,
      strokeGain: 1.2,
      minL: 38,
      maxL: 245,
    );

    final sharpenedGray = _unsharpMaskGray(grayL, w, h, sigma: 1.0, strength: 0.40);

    final rgb = Uint8List(w * h * 3);
    for (int i = 0; i < w * h; i++) {
      final v = sharpenedGray[i];
      rgb[i * 3] = v;
      rgb[i * 3 + 1] = v;
      rgb[i * 3 + 2] = v;
    }

    return img.Image.fromBytes(
      width: w,
      height: h,
      bytes: rgb.buffer,
      order: img.ChannelOrder.rgb,
      numChannels: 3,
    );
  }

  /// 4. Whiteboard: High-contrast glare-free board mode.
  static img.Image filterWhiteboard(PreprocessedDocument preproc) {
    final wbL = renderTonedLightness(
      preproc.normL,
      preproc.fineStrokeSignal,
      blackPt: 38,
      whitePt: 230,
      gamma: 1.60,
      strokeGain: 2.0,
    );
    final combined = combineColorChannels(
      wbL,
      preproc.aClean,
      preproc.bClean,
      preproc.width,
      preproc.height,
      chromaBoost: 3.2,
      liftDarkInk: true,
    );
    return unsharpMask(combined, sigma: 0.9, strength: 0.85);
  }

  /// 5. Black & White: Pure binary-style monochrome scan with sharpness-gated pencil amplification
  /// and clean sigmoid S-curve thresholding.
  static img.Image filterBlackAndWhite(PreprocessedDocument preproc) {
    final w = preproc.width;
    final h = preproc.height;
    final n = w * h;

    final enhanced = Uint8List(n);
    for (int i = 0; i < n; i++) {
      final v = preproc.normL[i].toDouble() - (preproc.fineStrokeSignal[i].toDouble() * 2.8);
      enhanced[i] = v.round().clamp(0, 255);
    }

    final smooth = _bilateralFilter5x5(enhanced, w, h, sigmaColor: 15.0, sigmaSpace: 15.0);

    final midpoint = 202.0;
    final steepness = 0.30;
    final sigmoidLut = Uint8List(256);
    for (int v = 0; v < 256; v++) {
      sigmoidLut[v] = (255.0 / (1.0 + math.exp(-steepness * (v - midpoint)))).round().clamp(0, 255);
    }

    final rgb = Uint8List(n * 3);
    for (int i = 0; i < n; i++) {
      final bw = sigmoidLut[smooth[i]];
      rgb[i * 3] = bw;
      rgb[i * 3 + 1] = bw;
      rgb[i * 3 + 2] = bw;
    }

    return img.Image.fromBytes(
      width: w,
      height: h,
      bytes: rgb.buffer,
      order: img.ChannelOrder.rgb,
      numChannels: 3,
    );
  }

  // ---------------------------------------------------------------------------
  // Algorithmic Math & Image Processing Helpers
  // ---------------------------------------------------------------------------

  static void _rgbToLab(Uint8List rgb, Uint8List labL, Uint8List labA, Uint8List labB) {
    final n = labL.length;
    for (int i = 0; i < n; i++) {
      final r = rgb[i * 3];
      final g = rgb[i * 3 + 1];
      final b = rgb[i * 3 + 2];

      final rf = _srgbToLinearTable[r];
      final gf = _srgbToLinearTable[g];
      final bf = _srgbToLinearTable[b];

      final x = (0.412453 * rf + 0.357580 * gf + 0.180423 * bf) / 0.950456;
      final y = (0.212671 * rf + 0.715160 * gf + 0.072169 * bf) / 1.000000;
      final z = (0.019334 * rf + 0.119193 * gf + 0.950227 * bf) / 1.088754;

      final fx = x > 0.008856 ? math.pow(x, 1.0 / 3.0).toDouble() : (7.787 * x + 16.0 / 116.0);
      final fy = y > 0.008856 ? math.pow(y, 1.0 / 3.0).toDouble() : (7.787 * y + 16.0 / 116.0);
      final fz = z > 0.008856 ? math.pow(z, 1.0 / 3.0).toDouble() : (7.787 * z + 16.0 / 116.0);

      labL[i] = ((116.0 * fy - 16.0) * 255.0 / 100.0).round().clamp(0, 255);
      labA[i] = (500.0 * (fx - fy) + 128.0).round().clamp(0, 255);
      labB[i] = (200.0 * (fy - fz) + 128.0).round().clamp(0, 255);
    }
  }

  static void _labToRgb(Uint8List labL, Uint8List labA, Uint8List labB, Uint8List outRgb) {
    final n = labL.length;
    for (int i = 0; i < n; i++) {
      final lVal = labL[i];
      final aVal = labA[i];
      final bVal = labB[i];

      final lf = lVal * 100.0 / 255.0;
      final af = aVal - 128.0;
      final bf = bVal - 128.0;

      final fy = (lf + 16.0) / 116.0;
      final fx = fy + af / 500.0;
      final fz = fy - bf / 200.0;

      final fx3 = fx * fx * fx;
      final fy3 = fy * fy * fy;
      final fz3 = fz * fz * fz;

      final x = (fx3 > 0.008856 ? fx3 : (fx - 16.0 / 116.0) / 7.787) * 0.950456;
      final y = (fy3 > 0.008856 ? fy3 : (fy - 16.0 / 116.0) / 7.787) * 1.000000;
      final z = (fz3 > 0.008856 ? fz3 : (fz - 16.0 / 116.0) / 7.787) * 1.088754;

      final rf = 3.2404542 * x - 1.5371385 * y - 0.4985314 * z;
      final gf = -0.9692660 * x + 1.8760108 * y + 0.0415560 * z;
      final bfVal = 0.0556434 * x - 0.2040259 * y + 1.0572252 * z;

      outRgb[i * 3] = (_linearToSrgb(rf) * 255.0).round().clamp(0, 255);
      outRgb[i * 3 + 1] = (_linearToSrgb(gf) * 255.0).round().clamp(0, 255);
      outRgb[i * 3 + 2] = (_linearToSrgb(bfVal) * 255.0).round().clamp(0, 255);
    }
  }

  static Float64List _getGaussianKernel(int ksize, double sigma) {
    final kernel = Float64List(ksize);
    final actualSigma = sigma <= 0.0 ? 0.3 * ((ksize - 1) * 0.5 - 1.0) + 0.8 : sigma;
    final scale2X = -0.5 / (actualSigma * actualSigma);
    final r = (ksize - 1) ~/ 2;
    double sum = 0.0;
    for (int i = 0; i < ksize; i++) {
      final x = i - r;
      final w = math.exp(scale2X * x * x);
      kernel[i] = w;
      sum += w;
    }
    for (int i = 0; i < ksize; i++) {
      kernel[i] /= sum;
    }
    return kernel;
  }

  static Uint8List _gaussianBlurUint8(Uint8List src, int w, int h, int ksize, double sigma) {
    if (ksize <= 0) {
      ksize = (sigma * 3).round() * 2 + 1;
    }
    if (ksize % 2 == 0) ksize += 1;
    if (ksize < 3) return Uint8List.fromList(src);

    final kernel = _getGaussianKernel(ksize, sigma);
    final r = (ksize - 1) ~/ 2;
    final temp = Float64List(w * h);
    final out = Uint8List(w * h);

    // Horizontal pass
    for (int y = 0; y < h; y++) {
      final rowOff = y * w;
      for (int x = 0; x < w; x++) {
        double sum = 0.0;
        for (int k = 0; k < ksize; k++) {
          final sx = (x + k - r).clamp(0, w - 1);
          sum += src[rowOff + sx] * kernel[k];
        }
        temp[rowOff + x] = sum;
      }
    }

    // Vertical pass
    for (int x = 0; x < w; x++) {
      for (int y = 0; y < h; y++) {
        double sum = 0.0;
        for (int k = 0; k < ksize; k++) {
          final sy = (y + k - r).clamp(0, h - 1);
          sum += temp[sy * w + x] * kernel[k];
        }
        out[y * w + x] = sum.round().clamp(0, 255);
      }
    }

    return out;
  }

  static Float32List _gaussianBlurFloat(Float32List src, int w, int h, int ksize, double sigma) {
    if (ksize <= 0) {
      ksize = (sigma * 3).round() * 2 + 1;
    }
    if (ksize % 2 == 0) ksize += 1;
    if (ksize < 3) return Float32List.fromList(src);

    final kernel = _getGaussianKernel(ksize, sigma);
    final r = (ksize - 1) ~/ 2;
    final temp = Float32List(w * h);
    final out = Float32List(w * h);

    for (int y = 0; y < h; y++) {
      final rowOff = y * w;
      for (int x = 0; x < w; x++) {
        double sum = 0.0;
        for (int k = 0; k < ksize; k++) {
          final sx = (x + k - r).clamp(0, w - 1);
          sum += src[rowOff + sx] * kernel[k];
        }
        temp[rowOff + x] = sum;
      }
    }

    for (int x = 0; x < w; x++) {
      for (int y = 0; y < h; y++) {
        double sum = 0.0;
        for (int k = 0; k < ksize; k++) {
          final sy = (y + k - r).clamp(0, h - 1);
          sum += temp[sy * w + x] * kernel[k];
        }
        out[y * w + x] = sum;
      }
    }

    return out;
  }

  static void _sobel3x3(Float32List src, int w, int h, Float32List gx, Float32List gy) {
    for (int y = 0; y < h; y++) {
      final yTop = (y - 1).clamp(0, h - 1) * w;
      final yMid = y * w;
      final yBot = (y + 1).clamp(0, h - 1) * w;

      for (int x = 0; x < w; x++) {
        final xL = (x - 1).clamp(0, w - 1);
        final xC = x;
        final xR = (x + 1).clamp(0, w - 1);

        final p00 = src[yTop + xL];
        final p01 = src[yTop + xC];
        final p02 = src[yTop + xR];

        final p10 = src[yMid + xL];
        final p12 = src[yMid + xR];

        final p20 = src[yBot + xL];
        final p21 = src[yBot + xC];
        final p22 = src[yBot + xR];

        gx[yMid + xC] = (-p00 + p02 - 2.0 * p10 + 2.0 * p12 - p20 + p22);
        gy[yMid + xC] = (-p00 - 2.0 * p01 - p02 + p20 + 2.0 * p21 + p22);
      }
    }
  }

  static Int32List _buildEllipseDxList(int k) {
    final r = k ~/ 2;
    final c = k ~/ 2;
    final dxList = Int32List(k);
    for (int i = 0; i < k; i++) {
      final dy = i - r;
      if (dy.abs() <= r) {
        final d = r > 0 ? dy.toDouble() / r : 0.0;
        final dx = c * math.sqrt(math.max(0.0, 1.0 - d * d));
        dxList[i] = dx.round();
      } else {
        dxList[i] = 0;
      }
    }
    return dxList;
  }

  static Uint8List _morphologyCloseEllipse(Uint8List src, int w, int h, int k) {
    final r = k ~/ 2;
    final dxList = _buildEllipseDxList(k);
    final uniqueDx = dxList.toSet().toList()..sort();

    // Dilation
    final rowMax = <int, Uint8List>{};
    for (final dx in uniqueDx) {
      final buf = Uint8List(w * h);
      for (int y = 0; y < h; y++) {
        final rowOff = y * w;
        for (int x = 0; x < w; x++) {
          final x0 = math.max(0, x - dx);
          final x1 = math.min(w - 1, x + dx);
          var maxV = src[rowOff + x0];
          for (int cx = x0 + 1; cx <= x1; cx++) {
            final v = src[rowOff + cx];
            if (v > maxV) maxV = v;
          }
          buf[rowOff + x] = maxV;
        }
      }
      rowMax[dx] = buf;
    }

    final dilated = Uint8List(w * h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        var maxV = 0;
        for (int i = 0; i < k; i++) {
          final dy = i - r;
          final sy = (y + dy).clamp(0, h - 1);
          final dx = dxList[i];
          final v = rowMax[dx]![sy * w + x];
          if (v > maxV) maxV = v;
        }
        dilated[y * w + x] = maxV;
      }
    }

    // Erosion
    final rowMin = <int, Uint8List>{};
    for (final dx in uniqueDx) {
      final buf = Uint8List(w * h);
      for (int y = 0; y < h; y++) {
        final rowOff = y * w;
        for (int x = 0; x < w; x++) {
          final x0 = math.max(0, x - dx);
          final x1 = math.min(w - 1, x + dx);
          var minV = dilated[rowOff + x0];
          for (int cx = x0 + 1; cx <= x1; cx++) {
            final v = dilated[rowOff + cx];
            if (v < minV) minV = v;
          }
          buf[rowOff + x] = minV;
        }
      }
      rowMin[dx] = buf;
    }

    final closed = Uint8List(w * h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        var minV = 255;
        for (int i = 0; i < k; i++) {
          final dy = i - r;
          final sy = (y + dy).clamp(0, h - 1);
          final dx = dxList[i];
          final v = rowMin[dx]![sy * w + x];
          if (v < minV) minV = v;
        }
        closed[y * w + x] = minV;
      }
    }
    return closed;
  }

  static Uint8List _dilateEllipse(Uint8List mask, int w, int h, int k) {
    final r = k ~/ 2;
    final dxList = _buildEllipseDxList(k);
    final out = Uint8List(w * h);

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        int hit = 0;
        for (int i = 0; i < k; i++) {
          final dy = i - r;
          final sy = y + dy;
          if (sy < 0 || sy >= h) continue;
          final dx = dxList[i];
          final x0 = math.max(0, x - dx);
          final x1 = math.min(w - 1, x + dx);
          final rowOff = sy * w;
          for (int sx = x0; sx <= x1; sx++) {
            if (mask[rowOff + sx] > 0) {
              hit = 255;
              break;
            }
          }
          if (hit == 255) break;
        }
        out[y * w + x] = hit;
      }
    }
    return out;
  }

  static Uint8List _erode2x2Ellipse(Uint8List src, int w, int h) {
    final out = Uint8List(w * h);
    for (int y = 0; y < h; y++) {
      final y0 = math.max(0, y - 1);
      final rUp = y0 * w;
      final rCur = y * w;
      for (int x = 0; x < w; x++) {
        final x0 = math.max(0, x - 1);
        final vUp = src[rUp + x];
        final vLeft = src[rCur + x0];
        final vSelf = src[rCur + x];
        out[rCur + x] = math.min(vSelf, math.min(vUp, vLeft));
      }
    }
    return out;
  }

  /// Telea FMM inpainting matching cv2.inpaint(..., inpaintRadius=7, flags=cv2.INPAINT_TELEA).
  /// Order of propagation is from the outside boundary of mask inwards, weighting by
  /// distance and gradient.
  static Uint8List _inpaintTelea(Uint8List image, Uint8List mask, int w, int h, {int radius = 7}) {
    final n = w * h;
    final result = Uint8List.fromList(image);
    final dist = Float32List(n);
    final isMask = Uint8List(n);

    // Compute approximate Euclidean distance transform for mask pixels
    for (int i = 0; i < n; i++) {
      if (mask[i] > 0) {
        dist[i] = 1e6;
        isMask[i] = 1;
      } else {
        dist[i] = 0.0;
        isMask[i] = 0;
      }
    }

    // Forward pass distance transform
    for (int y = 0; y < h; y++) {
      final row = y * w;
      for (int x = 0; x < w; x++) {
        final idx = row + x;
        if (isMask[idx] == 0) continue;
        var d = dist[idx];
        if (x > 0) d = math.min(d, dist[idx - 1] + 1.0);
        if (y > 0) d = math.min(d, dist[idx - w] + 1.0);
        if (x > 0 && y > 0) d = math.min(d, dist[idx - w - 1] + 1.414);
        if (x < w - 1 && y > 0) d = math.min(d, dist[idx - w + 1] + 1.414);
        dist[idx] = d;
      }
    }

    // Backward pass distance transform
    for (int y = h - 1; y >= 0; y--) {
      final row = y * w;
      for (int x = w - 1; x >= 0; x--) {
        final idx = row + x;
        if (isMask[idx] == 0) continue;
        var d = dist[idx];
        if (x < w - 1) d = math.min(d, dist[idx + 1] + 1.0);
        if (y < h - 1) d = math.min(d, dist[idx + w] + 1.0);
        if (x < w - 1 && y < h - 1) d = math.min(d, dist[idx + w + 1] + 1.414);
        if (x > 0 && y < h - 1) d = math.min(d, dist[idx + w - 1] + 1.414);
        dist[idx] = d;
      }
    }

    // Collect mask indices and sort by distance (boundary first)
    final maskIndices = <int>[];
    for (int i = 0; i < n; i++) {
      if (isMask[i] == 1) maskIndices.add(i);
    }
    maskIndices.sort((a, b) => dist[a].compareTo(dist[b]));

    final r2 = radius * radius;
    for (final p in maskIndices) {
      final py = p ~/ w;
      final px = p % w;
      double sumW = 0.0;
      double sumI = 0.0;

      final y0 = math.max(0, py - radius);
      final y1 = math.min(h - 1, py + radius);
      final x0 = math.max(0, px - radius);
      final x1 = math.min(w - 1, px + radius);

      for (int qy = y0; qy <= y1; qy++) {
        final qRow = qy * w;
        final dy = qy - py;
        for (int qx = x0; qx <= x1; qx++) {
          final dx = qx - px;
          final d2 = dx * dx + dy * dy;
          if (d2 > r2 || d2 == 0) continue;
          final q = qRow + qx;
          if (isMask[q] == 1) continue; // unknown yet

          final dGeom = math.sqrt(d2);
          final wDist = 1.0 / (dGeom * dGeom);
          final wLev = 1.0 / (1.0 + (dist[p] - dist[q]).abs());
          final wTot = wDist * wLev;

          sumI += wTot * result[q];
          sumW += wTot;
        }
      }

      if (sumW > 0.0) {
        result[p] = (sumI / sumW).round().clamp(0, 255);
        isMask[p] = 0; // marked known for inner layers
      }
    }

    return result;
  }

  static Uint8List _resizeArea(Uint8List src, int srcW, int srcH, int dstW, int dstH) {
    final out = Uint8List(dstW * dstH);
    final scaleX = srcW.toDouble() / dstW;
    final scaleY = srcH.toDouble() / dstH;

    for (int dy = 0; dy < dstH; dy++) {
      final sy0 = dy * scaleY;
      final sy1 = (dy + 1) * scaleY;
      final iy0 = sy0.toInt();
      final iy1 = math.min(srcH, sy1.ceil());

      for (int dx = 0; dx < dstW; dx++) {
        final sx0 = dx * scaleX;
        final sx1 = (dx + 1) * scaleX;
        final ix0 = sx0.toInt();
        final ix1 = math.min(srcW, sx1.ceil());

        double totalWeight = 0.0;
        double sum = 0.0;

        for (int y = iy0; y < iy1; y++) {
          final wy = math.min(y + 1.0, sy1) - math.max(y.toDouble(), sy0);
          if (wy <= 0.0) continue;
          final rowOff = y * srcW;
          for (int x = ix0; x < ix1; x++) {
            final wx = math.min(x + 1.0, sx1) - math.max(x.toDouble(), sx0);
            if (wx <= 0.0) continue;
            final w = wx * wy;
            sum += w * src[rowOff + x];
            totalWeight += w;
          }
        }
        out[dy * dstW + dx] = totalWeight > 0.0 ? (sum / totalWeight).round().clamp(0, 255) : 0;
      }
    }
    return out;
  }

  /// Bicubic resize matching OpenCV INTER_CUBIC (Catmull-Rom cubic spline with A = -0.75).
  static Uint8List _resizeBicubic(Uint8List src, int srcW, int srcH, int dstW, int dstH) {
    final out = Uint8List(dstW * dstH);
    final scaleX = srcW.toDouble() / dstW;
    final scaleY = srcH.toDouble() / dstH;

    double cubicCoeff(double t) {
      final a = -0.75;
      final at = t.abs();
      if (at <= 1.0) {
        return ((a + 2.0) * at - (a + 3.0)) * at * at + 1.0;
      } else if (at < 2.0) {
        return ((a * at - 5.0 * a) * at + 8.0 * a) * at - 4.0 * a;
      }
      return 0.0;
    }

    for (int dy = 0; dy < dstH; dy++) {
      final sy = (dy + 0.5) * scaleY - 0.5;
      final iy = sy.floor();
      final fy = sy - iy;

      final wy = Float64List(4);
      for (int j = 0; j < 4; j++) {
        wy[j] = cubicCoeff(fy - (j - 1));
      }

      for (int dx = 0; dx < dstW; dx++) {
        final sx = (dx + 0.5) * scaleX - 0.5;
        final ix = sx.floor();
        final fx = sx - ix;

        final wx = Float64List(4);
        for (int i = 0; i < 4; i++) {
          wx[i] = cubicCoeff(fx - (i - 1));
        }

        double sum = 0.0;
        double wSum = 0.0;
        for (int j = 0; j < 4; j++) {
          final py = (iy + j - 1).clamp(0, srcH - 1);
          final row = py * srcW;
          final wj = wy[j];
          for (int i = 0; i < 4; i++) {
            final px = (ix + i - 1).clamp(0, srcW - 1);
            final wVal = wj * wx[i];
            sum += wVal * src[row + px];
            wSum += wVal;
          }
        }
        out[dy * dstW + dx] = wSum != 0.0 ? (sum / wSum).round().clamp(0, 255) : 0;
      }
    }
    return out;
  }

  static Uint8List _bilateralFilter5x5(
    Uint8List src,
    int w,
    int h, {
    required double sigmaColor,
    required double sigmaSpace,
  }) {
    final out = Uint8List(w * h);
    const r = 2;
    final offsets = <math.Point<int>>[];
    final swList = <double>[];

    final spaceFactor = -0.5 / (sigmaSpace * sigmaSpace);
    final colorFactor = -0.5 / (sigmaColor * sigmaColor);

    for (int dy = -r; dy <= r; dy++) {
      for (int dx = -r; dx <= r; dx++) {
        if (dx * dx + dy * dy <= r * r) {
          offsets.add(math.Point(dx, dy));
          swList.add(math.exp((dx * dx + dy * dy) * spaceFactor));
        }
      }
    }

    final rangeWeights = Float64List(256);
    for (int d = 0; d < 256; d++) {
      rangeWeights[d] = math.exp((d * d) * colorFactor);
    }

    int reflect101(int p, int len) {
      if (p < 0) return -p;
      if (p >= len) return 2 * len - 2 - p;
      return p;
    }

    final numNeighbors = offsets.length;
    for (int y = 0; y < h; y++) {
      final rowOff = y * w;
      for (int x = 0; x < w; x++) {
        final centerVal = src[rowOff + x];
        double valSum = 0.0;
        double wSum = 0.0;

        for (int k = 0; k < numNeighbors; k++) {
          final off = offsets[k];
          final ny = reflect101(y + off.y, h);
          final nx = reflect101(x + off.x, w);
          final neighborVal = src[ny * w + nx];
          final diff = (neighborVal - centerVal).abs();
          final wVal = swList[k] * rangeWeights[diff];
          valSum += wVal * neighborVal;
          wSum += wVal;
        }
        out[rowOff + x] = (valSum / wSum).round().clamp(0, 255);
      }
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // Manual Adjustments
  // ---------------------------------------------------------------------------

  static img.Image _applyAdjustments(
    img.Image src, {
    double brightness = 0.0,
    double contrast = 0.0,
    double highlights = 0.0,
    double shadows = 0.0,
    double exposure = 0.0,
    double saturation = 0.0,
  }) {
    if (brightness == 0.0 &&
        contrast == 0.0 &&
        highlights == 0.0 &&
        shadows == 0.0 &&
        exposure == 0.0 &&
        saturation == 0.0) {
      return src;
    }
    final result = img.Image.from(src);
    final cFactor = math.max(0.0, 1.0 + contrast);
    final bOffset = brightness * 255.0;
    final expMultiplier = math.pow(2.0, exposure).toDouble();
    final satFactor = math.max(0.0, 1.0 + saturation);

    for (final pixel in result) {
      var r = pixel.r.toDouble();
      var g = pixel.g.toDouble();
      var b = pixel.b.toDouble();

      // Exposure adjustment
      if (exposure != 0.0) {
        r *= expMultiplier;
        g *= expMultiplier;
        b *= expMultiplier;
      }

      // Brightness adjustment
      if (brightness != 0.0) {
        r += bOffset;
        g += bOffset;
        b += bOffset;
      }

      // Contrast adjustment
      if (contrast != 0.0) {
        r = (r - 128.0) * cFactor + 128.0;
        g = (g - 128.0) * cFactor + 128.0;
        b = (b - 128.0) * cFactor + 128.0;
      }

      // Highlights and Shadows adjustment
      if (highlights != 0.0 || shadows != 0.0) {
        final lum = 0.299 * r + 0.587 * g + 0.114 * b;
        if (highlights != 0.0 && lum > 128.0) {
          final hDelta = highlights * (lum - 128.0) * 0.5;
          r += hDelta;
          g += hDelta;
          b += hDelta;
        }
        if (shadows != 0.0 && lum < 128.0) {
          final sDelta = shadows * (128.0 - lum) * 0.5;
          r += sDelta;
          g += sDelta;
          b += sDelta;
        }
      }

      // Saturation adjustment
      if (saturation != 0.0) {
        final lum = 0.299 * r + 0.587 * g + 0.114 * b;
        r = lum + (r - lum) * satFactor;
        g = lum + (g - lum) * satFactor;
        b = lum + (b - lum) * satFactor;
      }

      pixel.r = r.round().clamp(0, 255);
      pixel.g = g.round().clamp(0, 255);
      pixel.b = b.round().clamp(0, 255);
    }
    return result;
  }

  static img.Image _applyHaloFreeSharpen(img.Image src, double sharpness) {
    final result = img.Image.from(src);
    final w = src.width;
    final h = src.height;
    final amount = sharpness.clamp(0.0, 1.0) * 1.5;

    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final p = src.getPixel(x, y);
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

        final target = result.getPixel(x, y);
        target.r = (p.r + rBoost).round().clamp(0, 255);
        target.g = (p.g + gBoost).round().clamp(0, 255);
        target.b = (p.b + bBoost).round().clamp(0, 255);
      }
    }
    return result;
  }
}
