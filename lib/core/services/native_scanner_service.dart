import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../models/models.dart';
import 'corner_detector_service.dart';

/// Native Android bridge for high-performance CameraX, TFLite inference,
/// homography perspective correction, and image filtering.
class NativeScannerService {
  static const MethodChannel _processingChannel = MethodChannel('com.docuray/document_processing');

  static bool get isNativeSupported => !kIsWeb && Platform.isAndroid;

  /// Unified single-pass native pipeline for real-time preview and export:
  /// EXIF rotation -> Homography warp -> Rotation -> Filter -> Adjustments -> Compression
  static Future<String?> processPage(
    String path, {
    List<double>? points,
    int degrees = 0,
    String filter = 'original',
    double brightness = 0.0,
    double contrast = 0.0,
    double sharpness = 0.0,
    int maxDimension = 0,
    int quality = 90,
  }) async {
    if (!isNativeSupported) return null;
    try {
      final res = await _processingChannel.invokeMethod<String>(
        'processPage',
        {
          'path': path,
          'points': ?points,
          'degrees': degrees,
          'filter': filter,
          'brightness': brightness,
          'contrast': contrast,
          'sharpness': sharpness,
          'maxDimension': maxDimension,
          'quality': quality,
        },
      );
      return res;
    } catch (e) {
      debugPrint('[NativeScannerService] processPage error: $e');
      return null;
    }
  }

  /// Runs corner detection on an image path using native TFLite
  static Future<DetectionResult?> detectCorners(String path) async {
    if (!isNativeSupported) return null;
    try {
      final res = await _processingChannel.invokeMapMethod<String, dynamic>(
        'detectCorners',
        {'path': path},
      );
      if (res == null) return null;

      final rawCorners = (res['corners'] as List?)?.map((e) => (e as num).toDouble()).toList() ?? [];
      final confidence = (res['confidence'] as num?)?.toDouble() ?? 0.0;
      final isValid = res['isValid'] as bool? ?? false;

      if (!isValid || rawCorners.length < 8) {
        return DetectionResult(
          corners: DetectionResult.defaultResult.corners,
          confidence: confidence,
          isValid: false,
        );
      }

      final corners = [
        CornerPoint(rawCorners[0], rawCorners[1]),
        CornerPoint(rawCorners[2], rawCorners[3]),
        CornerPoint(rawCorners[4], rawCorners[5]),
        CornerPoint(rawCorners[6], rawCorners[7]),
      ];

      return DetectionResult(
        corners: corners,
        confidence: confidence,
        isValid: true,
      );
    } catch (e) {
      debugPrint('[NativeScannerService] detectCorners error: $e');
      return null;
    }
  }

  /// Crops and perspective-warps an image with homography using native Matrix
  static Future<String?> cropImage(String path, List<double> points) async {
    if (!isNativeSupported) return null;
    try {
      final res = await _processingChannel.invokeMethod<String>(
        'cropImage',
        {'path': path, 'points': points},
      );
      return res;
    } catch (e) {
      debugPrint('[NativeScannerService] cropImage error: $e');
      return null;
    }
  }

  /// Rotates an image natively
  static Future<String?> rotateImage(String path, int degrees) async {
    if (!isNativeSupported) return null;
    try {
      final res = await _processingChannel.invokeMethod<String>(
        'rotateImage',
        {'path': path, 'degrees': degrees},
      );
      return res;
    } catch (e) {
      debugPrint('[NativeScannerService] rotateImage error: $e');
      return null;
    }
  }

  /// Applies document filters natively (Auto, Color, Grayscale, B&W)
  static Future<String?> applyFilter(String path, String filter) async {
    if (!isNativeSupported) return null;
    try {
      final res = await _processingChannel.invokeMethod<String>(
        'applyFilter',
        {'path': path, 'filter': filter},
      );
      return res;
    } catch (e) {
      debugPrint('[NativeScannerService] applyFilter error: $e');
      return null;
    }
  }

  /// Applies image adjustments natively
  static Future<String?> adjustImage(
    String path, {
    double brightness = 0.0,
    double contrast = 0.0,
    double exposure = 0.0,
    double sharpness = 0.0,
  }) async {
    if (!isNativeSupported) return null;
    try {
      final res = await _processingChannel.invokeMethod<String>(
        'adjustImage',
        {
          'path': path,
          'brightness': brightness,
          'contrast': contrast,
          'exposure': exposure,
          'sharpness': sharpness,
        },
      );
      return res;
    } catch (e) {
      debugPrint('[NativeScannerService] adjustImage error: $e');
      return null;
    }
  }
}
