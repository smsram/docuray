import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import '../../models/models.dart';

/// Detection result containing four normalized corners and confidence score.
class DetectionResult {
  final List<CornerPoint> corners; // [TL, TR, BR, BL] in normalized 0..1 space
  final double confidence;
  final bool isValid;
  final bool isTightlyFramed;
  final double areaRatio;
  final Map<String, dynamic>? metrics;

  const DetectionResult({
    required this.corners,
    required this.confidence,
    required this.isValid,
    this.isTightlyFramed = false,
    this.areaRatio = 0.0,
    this.metrics,
  });

  static const defaultResult = DetectionResult(
    corners: [
      CornerPoint(0.05, 0.05),
      CornerPoint(0.95, 0.05),
      CornerPoint(0.95, 0.95),
      CornerPoint(0.05, 0.95),
    ],
    confidence: 0.0,
    isValid: false,
    isTightlyFramed: true,
  );
}

class PaperCornerDetector {
  static const String modelAsset = 'assets/models/best.tflite';
  static const int inputSize = 640;
  static const int protoSize = 160;
  static const int numProtos = 32;
  static const int numAnchors = 8400;
  static const double minConfidenceThreshold = 0.25;
  static const double minDocumentArea = 0.07;
  static const double maxDocumentArea = 0.96;

  Isolate? _workerIsolate;
  SendPort? _workerSendPort;
  bool _isInitialized = false;
  bool _isInitializing = false;

  // Temporal stabilization on main isolate
  List<CornerPoint>? _stabilizedCorners;
  int _consecutiveStableFrames = 0;

  bool get isInitialized => _isInitialized;
  int get consecutiveStableFrames => _consecutiveStableFrames;

  Future<void> initialize() async {
    if (_isInitialized || _isInitializing) return;
    _isInitializing = true;

    try {
      // Load raw model bytes on main isolate so background isolate doesn't need platform channels
      final modelByteData = await rootBundle.load(modelAsset);
      final modelBytes = modelByteData.buffer.asUint8List();

      final receivePort = ReceivePort();
      _workerIsolate = await Isolate.spawn(
        _workerMain,
        _WorkerInitConfig(
          sendPort: receivePort.sendPort,
          modelBytes: TransferableTypedData.fromList([modelBytes]),
          isAndroid: !kIsWeb && Platform.isAndroid,
        ),
      );

      _workerSendPort = await receivePort.first as SendPort?;
      _isInitialized = _workerSendPort != null;
      debugPrint('[DocuRay] Background TFLite Isolate initialized: $_isInitialized');
    } catch (e) {
      debugPrint('[DocuRay] Error spawning PaperCornerDetector Isolate: $e');
      _isInitialized = false;
    } finally {
      _isInitializing = false;
    }
  }

  void dispose() {
    _workerIsolate?.kill(priority: Isolate.immediate);
    _workerIsolate = null;
    _workerSendPort = null;
    _isInitialized = false;
    _stabilizedCorners = null;
  }

  Future<DetectionResult> detectCornersFromCameraImage(
    CameraImage cameraImage, {
    int sensorOrientation = 90,
  }) async {
    if (!_isInitialized || _workerSendPort == null) {
      await initialize();
      if (!_isInitialized || _workerSendPort == null) {
        return DetectionResult.defaultResult;
      }
    }

    try {
      final hasYuv = cameraImage.planes.length >= 3;
      final yBytes = cameraImage.planes[0].bytes;
      final uBytes = hasYuv ? cameraImage.planes[1].bytes : Uint8List(0);
      final vBytes = hasYuv ? cameraImage.planes[2].bytes : Uint8List(0);

      final planesData = <Uint8List>[
        yBytes,
        if (hasYuv) uBytes,
        if (hasYuv) vBytes,
      ];

      final replyPort = ReceivePort();
      _workerSendPort!.send(
        _CameraFrameRequest(
          replyPort: replyPort.sendPort,
          width: cameraImage.width,
          height: cameraImage.height,
          sensorOrientation: sensorOrientation,
          hasYuvPlanes: hasYuv,
          yRowStride: cameraImage.planes[0].bytesPerRow,
          uRowStride: hasYuv ? cameraImage.planes[1].bytesPerRow : 0,
          vRowStride: hasYuv ? cameraImage.planes[2].bytesPerRow : 0,
          uPixelStride: hasYuv ? (cameraImage.planes[1].bytesPerPixel ?? 1) : 1,
          vPixelStride: hasYuv ? (cameraImage.planes[2].bytesPerPixel ?? 1) : 1,
          yPlaneLen: yBytes.length,
          uPlaneLen: uBytes.length,
          vPlaneLen: vBytes.length,
          planes: TransferableTypedData.fromList(planesData),
        ),
      );

      final rawRes = await replyPort.first as Map<String, dynamic>;
      return _processWorkerResponse(rawRes);
    } catch (e) {
      debugPrint('[DocuRay] Live camera isolate error: $e');
      return DetectionResult.defaultResult;
    }
  }

  Future<DetectionResult> detectCornersFromPath(String path) async {
    try {
      // Decode, bake EXIF orientation, and downscale in background isolate to prevent ANR freeze
      final rgbData = await Isolate.run(() async {
        final bytes = await File(path).readAsBytes();
        final decoded = img.decodeImage(bytes);
        if (decoded == null) return null;
        final oriented = img.bakeOrientation(decoded);
        final scale = math.min(inputSize / oriented.width, inputSize / oriented.height);
        final scaledW = (oriented.width * scale).round();
        final scaledH = (oriented.height * scale).round();
        final resized = img.copyResize(oriented, width: scaledW, height: scaledH);
        return {
          'w': scaledW,
          'h': scaledH,
          'bytes': resized.getBytes(order: img.ChannelOrder.rgb),
        };
      });

      if (rgbData == null) return DetectionResult.defaultResult;

      if (!_isInitialized || _workerSendPort == null) {
        await initialize();
        if (!_isInitialized || _workerSendPort == null) {
          return DetectionResult.defaultResult;
        }
      }

      final replyPort = ReceivePort();
      _workerSendPort!.send(
        _StaticImageRequest(
          replyPort: replyPort.sendPort,
          scaledW: rgbData['w'] as int,
          scaledH: rgbData['h'] as int,
          rgbBytes: TransferableTypedData.fromList([rgbData['bytes'] as Uint8List]),
        ),
      );

      final rawRes = await replyPort.first as Map<String, dynamic>;
      return _processWorkerResponse(rawRes);
    } catch (e) {
      debugPrint('[DocuRay] detectCornersFromPath error: $e');
      return DetectionResult.defaultResult;
    }
  }

  Future<DetectionResult> detectCorners(img.Image inputImage) async {
    if (!_isInitialized || _workerSendPort == null) {
      await initialize();
      if (!_isInitialized || _workerSendPort == null) {
        return DetectionResult.defaultResult;
      }
    }

    try {
      final imgW = inputImage.width;
      final imgH = inputImage.height;
      final scale = math.min(inputSize / imgW, inputSize / imgH);
      final scaledW = (imgW * scale).round();
      final scaledH = (imgH * scale).round();

      final resized = img.copyResize(inputImage, width: scaledW, height: scaledH);
      final rgbBytes = resized.getBytes(order: img.ChannelOrder.rgb);

      final replyPort = ReceivePort();
      _workerSendPort!.send(
        _StaticImageRequest(
          replyPort: replyPort.sendPort,
          scaledW: scaledW,
          scaledH: scaledH,
          rgbBytes: TransferableTypedData.fromList([rgbBytes]),
        ),
      );

      final rawRes = await replyPort.first as Map<String, dynamic>;
      return _processWorkerResponse(rawRes);
    } catch (e) {
      debugPrint('[DocuRay] Static image isolate error: $e');
      return DetectionResult.defaultResult;
    }
  }

  DetectionResult _processWorkerResponse(Map<String, dynamic> rawRes) {
    final bool isValid = rawRes['isValid'] as bool? ?? false;
    final double confidence = (rawRes['confidence'] as num?)?.toDouble() ?? 0.0;
    final double areaRatio = (rawRes['areaRatio'] as num?)?.toDouble() ?? 0.0;
    final Map<String, dynamic>? metrics = rawRes['metrics'] as Map<String, dynamic>?;

    if (!isValid) {
      _consecutiveStableFrames = 0;
      return DetectionResult(
        corners: _stabilizedCorners ?? DetectionResult.defaultResult.corners,
        confidence: confidence,
        isValid: false,
        areaRatio: areaRatio,
        metrics: metrics,
      );
    }

    final rawList = (rawRes['corners'] as List).cast<double>();
    final strictCorners = [
      CornerPoint(rawList[0], rawList[1]),
      CornerPoint(rawList[2], rawList[3]),
      CornerPoint(rawList[4], rawList[5]),
      CornerPoint(rawList[6], rawList[7]),
    ];

    final smoothed = _applyTemporalStabilization(strictCorners);
    return DetectionResult(
      corners: smoothed,
      confidence: confidence,
      isValid: true,
      areaRatio: areaRatio,
      metrics: metrics,
    );
  }

  List<CornerPoint> _applyTemporalStabilization(List<CornerPoint> newCorners) {
    if (_stabilizedCorners == null || _stabilizedCorners!.length != 4) {
      _stabilizedCorners = newCorners;
      _consecutiveStableFrames = 1;
      return newCorners;
    }

    double maxShift = 0.0;
    for (int i = 0; i < 4; i++) {
      final dx = newCorners[i].x - _stabilizedCorners![i].x;
      final dy = newCorners[i].y - _stabilizedCorners![i].y;
      final shift = math.sqrt(dx * dx + dy * dy);
      if (shift > maxShift) maxShift = shift;
    }

    if (maxShift < 0.04) {
      _consecutiveStableFrames++;
    } else {
      _consecutiveStableFrames = 1;
    }

    const alpha = 0.55;
    final smoothed = List.generate(4, (i) {
      return CornerPoint(
        alpha * newCorners[i].x + (1.0 - alpha) * _stabilizedCorners![i].x,
        alpha * newCorners[i].y + (1.0 - alpha) * _stabilizedCorners![i].y,
      );
    });

    _stabilizedCorners = smoothed;
    return smoothed;
  }

  void resetStabilization() {
    _stabilizedCorners = null;
    _consecutiveStableFrames = 0;
  }
}

// ============================================================================
// BACKGROUND WORKER ISOLATE MESSAGES & ZERO-COPY ENGINE
// ============================================================================

class _WorkerInitConfig {
  final SendPort sendPort;
  final TransferableTypedData modelBytes;
  final bool isAndroid;

  const _WorkerInitConfig({
    required this.sendPort,
    required this.modelBytes,
    required this.isAndroid,
  });
}

class _CameraFrameRequest {
  final SendPort replyPort;
  final int width;
  final int height;
  final int sensorOrientation;
  final bool hasYuvPlanes;
  final int yRowStride;
  final int uRowStride;
  final int vRowStride;
  final int uPixelStride;
  final int vPixelStride;
  final int yPlaneLen;
  final int uPlaneLen;
  final int vPlaneLen;
  final TransferableTypedData planes;

  const _CameraFrameRequest({
    required this.replyPort,
    required this.width,
    required this.height,
    required this.sensorOrientation,
    required this.hasYuvPlanes,
    required this.yRowStride,
    required this.uRowStride,
    required this.vRowStride,
    required this.uPixelStride,
    required this.vPixelStride,
    required this.yPlaneLen,
    required this.uPlaneLen,
    required this.vPlaneLen,
    required this.planes,
  });
}

class _StaticImageRequest {
  final SendPort replyPort;
  final int scaledW;
  final int scaledH;
  final TransferableTypedData rgbBytes;

  const _StaticImageRequest({
    required this.replyPort,
    required this.scaledW,
    required this.scaledH,
    required this.rgbBytes,
  });
}

class _CandidateDocument {
  final int anchor;
  final double score;
  final double areaRatio;
  final List<math.Point<double>> boundaryPoints;

  const _CandidateDocument({
    required this.anchor,
    required this.score,
    required this.areaRatio,
    required this.boundaryPoints,
  });
}

/// Entry point for the persistent background TFLite worker isolate
void _workerMain(_WorkerInitConfig config) {
  final receivePort = ReceivePort();
  final engine = _IsolateTFLiteEngine();

  final ok = engine.init(
    config.modelBytes.materialize().asUint8List(),
    isAndroid: config.isAndroid,
  );

  if (!ok) {
    config.sendPort.send(null);
    return;
  }

  config.sendPort.send(receivePort.sendPort);

  receivePort.listen((message) {
    if (message is _CameraFrameRequest) {
      final res = engine.processCameraFrame(message);
      message.replyPort.send(res);
    } else if (message is _StaticImageRequest) {
      final res = engine.processStaticImage(message);
      message.replyPort.send(res);
    }
  });
}

class _IsolateTFLiteEngine {
  static const int inputSize = PaperCornerDetector.inputSize;
  static const int protoSize = PaperCornerDetector.protoSize;
  static const int numProtos = PaperCornerDetector.numProtos;
  static const int numAnchors = PaperCornerDetector.numAnchors;
  static const double minConfidenceThreshold = PaperCornerDetector.minConfidenceThreshold;
  static const double minDocumentArea = PaperCornerDetector.minDocumentArea;
  static const double maxDocumentArea = PaperCornerDetector.maxDocumentArea;

  Interpreter? _interpreter;
  String _activeBackend = 'CPU';

  bool _isInputNHWC = true;
  bool _isProtoNHWC = true;
  bool _isPredTransposed = false;
  int _predOutIndex = 0;
  int _protoOutIndex = 1;

  // FLAT zero-copy Float32List buffers (eliminates 3.5M nested List copies!)
  late Float32List _inputBuffer;
  late Float32List _outputPredsFlat;
  late Float32List _outputProtosFlat;
  late List<Uint8List> _maskGrid;
  late Float32List _maskAccFlat;

  final Int32List _rTableV = Int32List(256);
  final Int32List _gTableU = Int32List(256);
  final Int32List _gTableV = Int32List(256);
  final Int32List _bTableU = Int32List(256);
  final Float32List _lutNorm255 = Float32List(256);

  bool init(Uint8List modelBytes, {required bool isAndroid}) {
    try {
      for (int i = 0; i < 256; i++) {
        _lutNorm255[i] = i / 255.0;
        final uv = i - 128;
        _rTableV[i] = (1.402 * uv * 1024).round();
        _gTableU[i] = (-0.344136 * uv * 1024).round();
        _gTableV[i] = (-0.714136 * uv * 1024).round();
        _bTableU[i] = (1.772 * uv * 1024).round();
      }

      final options = InterpreterOptions()..threads = 4;
      if (isAndroid) {
        try {
          options.addDelegate(XNNPackDelegate());
          _activeBackend = 'XNNPACK';
        } catch (_) {
          _activeBackend = 'CPU (4T)';
        }
      }

      _interpreter = Interpreter.fromBuffer(modelBytes, options: options);
      _interpreter!.allocateTensors();

      final inputShape = _interpreter!.getInputTensor(0).shape;
      _isInputNHWC = inputShape.length == 4 && inputShape[3] == 3;

      final out0Shape = _interpreter!.getOutputTensor(0).shape;
      final out1Shape = _interpreter!.getOutputTensor(1).shape;

      if (out0Shape.length == 4 && out1Shape.length == 3) {
        _protoOutIndex = 0;
        _predOutIndex = 1;
      } else {
        _predOutIndex = 0;
        _protoOutIndex = 1;
      }

      final predShape = _interpreter!.getOutputTensor(_predOutIndex).shape;
      final protoShape = _interpreter!.getOutputTensor(_protoOutIndex).shape;

      _isPredTransposed = predShape[1] == numAnchors;
      _isProtoNHWC = protoShape.length == 4 && protoShape[3] == numProtos;

      // Allocate flat typed buffers once
      _inputBuffer = Float32List(1 * 3 * inputSize * inputSize);
      _outputPredsFlat = Float32List(1 * 37 * numAnchors);
      _outputProtosFlat = Float32List(1 * protoSize * protoSize * numProtos);
      _maskGrid = List.generate(protoSize, (_) => Uint8List(protoSize));
      _maskAccFlat = Float32List(protoSize * protoSize);

      return true;
    } catch (e) {
      debugPrint('[DocuRay] Worker init error: $e');
      return false;
    }
  }

  Map<String, dynamic> processCameraFrame(_CameraFrameRequest req) {
    final totalSw = Stopwatch()..start();
    try {
      final width = req.width;
      final height = req.height;
      final sensorOrientation = req.sensorOrientation;

      final bool isRotated90 = sensorOrientation == 90 || sensorOrientation == 270;
      final rotW = isRotated90 ? height : width;
      final rotH = isRotated90 ? width : height;

      final scale = math.min(inputSize / rotW, inputSize / rotH);
      final scaledW = (rotW * scale).round();
      final scaledH = (rotH * scale).round();
      final padX = (inputSize - scaledW) ~/ 2;
      final padY = (inputSize - scaledH) ~/ 2;

      _inputBuffer.fillRange(0, _inputBuffer.length, 114.0 / 255.0);
      final planeSize = inputSize * inputSize;

      final materialized = req.planes.materialize().asUint8List();

      if (req.hasYuvPlanes && req.yPlaneLen > 0) {
        final yBytes = Uint8List.sublistView(materialized, 0, req.yPlaneLen);
        final uBytes = Uint8List.sublistView(materialized, req.yPlaneLen, req.yPlaneLen + req.uPlaneLen);
        final vBytes = Uint8List.sublistView(materialized, req.yPlaneLen + req.uPlaneLen, req.yPlaneLen + req.uPlaneLen + req.vPlaneLen);

        final origXTable = Int32List(scaledW);
        for (int sx = 0; sx < scaledW; sx++) {
          origXTable[sx] = (sx / scale).clamp(0, rotW - 1).toInt();
        }

        final origYTable = Int32List(scaledH);
        for (int sy = 0; sy < scaledH; sy++) {
          origYTable[sy] = (sy / scale).clamp(0, rotH - 1).toInt();
        }

        final yMax = yBytes.length;
        final uMax = uBytes.length;
        final vMax = vBytes.length;

        for (int sy = 0; sy < scaledH; sy++) {
          final targetY = padY + sy;
          final origY = origYTable[sy];
          final targetYOffset = targetY * inputSize;

          for (int sx = 0; sx < scaledW; sx++) {
            final targetX = padX + sx;
            final origX = origXTable[sx];

            int srcX, srcY;
            if (sensorOrientation == 90) {
              srcX = origY;
              srcY = height - 1 - origX;
            } else if (sensorOrientation == 270) {
              srcX = width - 1 - origY;
              srcY = origX;
            } else if (sensorOrientation == 180) {
              srcX = width - 1 - origX;
              srcY = height - 1 - origY;
            } else {
              srcX = origX;
              srcY = origY;
            }

            final yIndex = srcY * req.yRowStride + srcX;
            final halfSrcY = srcY >> 1;
            final halfSrcX = srcX >> 1;
            final uvIndex = halfSrcY * req.uRowStride + halfSrcX * req.uPixelStride;
            final vIndex = halfSrcY * req.vRowStride + halfSrcX * req.vPixelStride;

            final int yVal = (yIndex >= 0 && yIndex < yMax) ? yBytes[yIndex] : 128;
            final int uByte = (uvIndex >= 0 && uvIndex < uMax) ? uBytes[uvIndex] : 128;
            final int vByte = (vIndex >= 0 && vIndex < vMax) ? vBytes[vIndex] : 128;

            final int y1024 = yVal << 10;
            final int rVal = ((y1024 + _rTableV[vByte]) >> 10).clamp(0, 255);
            final int gVal = ((y1024 + _gTableU[uByte] + _gTableV[vByte]) >> 10).clamp(0, 255);
            final int bVal = ((y1024 + _bTableU[uByte]) >> 10).clamp(0, 255);

            final double r = _lutNorm255[rVal];
            final double g = _lutNorm255[gVal];
            final double b = _lutNorm255[bVal];

            if (_isInputNHWC) {
              final idx = (targetYOffset + targetX) * 3;
              _inputBuffer[idx] = r;
              _inputBuffer[idx + 1] = g;
              _inputBuffer[idx + 2] = b;
            } else {
              final pixelIdx = targetYOffset + targetX;
              _inputBuffer[pixelIdx] = r;
              _inputBuffer[planeSize + pixelIdx] = g;
              _inputBuffer[2 * planeSize + pixelIdx] = b;
            }
          }
        }
      }

      // ZERO-COPY NATIVE TENSOR EXECUTION (< 1ms memory transfer)
      final inferSw = Stopwatch()..start();
      _interpreter!.getInputTensor(0).setTo(_inputBuffer.buffer);
      _interpreter!.invoke();
      _interpreter!.getOutputTensor(_predOutIndex).copyTo(_outputPredsFlat.buffer);
      _interpreter!.getOutputTensor(_protoOutIndex).copyTo(_outputProtosFlat.buffer);
      inferSw.stop();

      final postSw = Stopwatch()..start();
      final decoded = _decodeOutput(padX, padY, scaledW, scaledH);
      postSw.stop();
      totalSw.stop();

      final totalMs = totalSw.elapsedMicroseconds / 1000.0;
      decoded['metrics'] = {
        'fps': totalMs > 0 ? 1000.0 / totalMs : 0.0,
        'totalMs': totalMs,
        'inferenceMs': inferSw.elapsedMicroseconds / 1000.0,
        'decodeMs': postSw.elapsedMicroseconds / 1000.0,
        'maskMs': 0.0,
        'contourMs': 0.0,
        'backend': _activeBackend,
        'confidence': decoded['confidence'],
        'hasDocument': decoded['isValid'],
      };
      return decoded;
    } catch (e) {
      return {'isValid': false, 'confidence': 0.0, 'areaRatio': 0.0};
    }
  }

  Map<String, dynamic> processStaticImage(_StaticImageRequest req) {
    try {
      final scaledW = req.scaledW;
      final scaledH = req.scaledH;
      final padX = (inputSize - scaledW) ~/ 2;
      final padY = (inputSize - scaledH) ~/ 2;
      final rgb = req.rgbBytes.materialize().asUint8List();

      _inputBuffer.fillRange(0, _inputBuffer.length, 114.0 / 255.0);
      final planeSize = inputSize * inputSize;

      int srcIdx = 0;
      for (int sy = 0; sy < scaledH; sy++) {
        final targetYOffset = (padY + sy) * inputSize;
        for (int sx = 0; sx < scaledW; sx++) {
          final targetX = padX + sx;
          final r = _lutNorm255[rgb[srcIdx]];
          final g = _lutNorm255[rgb[srcIdx + 1]];
          final b = _lutNorm255[rgb[srcIdx + 2]];
          srcIdx += 3;

          if (_isInputNHWC) {
            final idx = (targetYOffset + targetX) * 3;
            _inputBuffer[idx] = r;
            _inputBuffer[idx + 1] = g;
            _inputBuffer[idx + 2] = b;
          } else {
            final pixelIdx = targetYOffset + targetX;
            _inputBuffer[pixelIdx] = r;
            _inputBuffer[planeSize + pixelIdx] = g;
            _inputBuffer[2 * planeSize + pixelIdx] = b;
          }
        }
      }

      _interpreter!.getInputTensor(0).setTo(_inputBuffer.buffer);
      _interpreter!.invoke();
      _interpreter!.getOutputTensor(_predOutIndex).copyTo(_outputPredsFlat.buffer);
      _interpreter!.getOutputTensor(_protoOutIndex).copyTo(_outputProtosFlat.buffer);

      return _decodeOutput(padX, padY, scaledW, scaledH);
    } catch (e) {
      return {'isValid': false, 'confidence': 0.0, 'areaRatio': 0.0};
    }
  }

  @pragma('vm:prefer-inline')
  double _getPredVal(int channel, int anchor) {
    if (_isPredTransposed) {
      return _outputPredsFlat[anchor * 37 + channel];
    } else {
      return _outputPredsFlat[channel * numAnchors + anchor];
    }
  }

  Map<String, dynamic> _decodeOutput(
    int padX,
    int padY,
    int scaledW,
    int scaledH,
  ) {
    final padX160 = padX / 4.0;
    final padY160 = padY / 4.0;
    final scaledW160 = scaledW / 4.0;
    final scaledH160 = scaledH / 4.0;
    final activeArea160 = scaledW160 * scaledH160;

    final minActiveX = padX160.floor().clamp(0, protoSize - 1);
    final minActiveY = padY160.floor().clamp(0, protoSize - 1);
    final maxActiveX = (padX160 + scaledW160).ceil().clamp(1, protoSize);
    final maxActiveY = (padY160 + scaledH160).ceil().clamp(1, protoSize);

    final candidateIndices = <int>[];
    for (int i = 0; i < numAnchors; i++) {
      if (_getPredVal(4, i) >= minConfidenceThreshold) {
        candidateIndices.add(i);
      }
    }

    if (candidateIndices.isEmpty) {
      return {'isValid': false, 'confidence': 0.0, 'areaRatio': 0.0};
    }

    candidateIndices.sort((a, b) => _getPredVal(4, b).compareTo(_getPredVal(4, a)));

    final keptAnchors = <int>[];
    final keptBoxes = <List<double>>[];

    for (final anchor in candidateIndices) {
      final rawCx = _getPredVal(0, anchor);
      final rawCy = _getPredVal(1, anchor);
      final rawBw = _getPredVal(2, anchor);
      final rawBh = _getPredVal(3, anchor);

      final isPixelSpace = rawCx > 1.5 || rawCy > 1.5 || rawBw > 1.5 || rawBh > 1.5;
      final normCx = isPixelSpace ? rawCx / inputSize : rawCx;
      final normCy = isPixelSpace ? rawCy / inputSize : rawCy;
      final normBw = isPixelSpace ? rawBw / inputSize : rawBw;
      final normBh = isPixelSpace ? rawBh / inputSize : rawBh;

      final x1 = normCx - normBw / 2.0;
      final y1 = normCy - normBh / 2.0;
      final x2 = normCx + normBw / 2.0;
      final y2 = normCy + normBh / 2.0;

      bool suppressed = false;
      for (int k = 0; k < keptBoxes.length; k++) {
        final b = keptBoxes[k];
        final xx1 = math.max(x1, b[0]);
        final yy1 = math.max(y1, b[1]);
        final xx2 = math.min(x2, b[2]);
        final yy2 = math.min(y2, b[3]);

        final interW = math.max(0.0, xx2 - xx1);
        final interH = math.max(0.0, yy2 - yy1);
        final interArea = interW * interH;

        final area1 = (x2 - x1) * (y2 - y1);
        final area2 = (b[2] - b[0]) * (b[3] - b[1]);
        final iou = interArea / (area1 + area2 - interArea + 1e-6);

        if (iou > 0.45) {
          suppressed = true;
          break;
        }
      }

      if (!suppressed) {
        keptAnchors.add(anchor);
        keptBoxes.add([x1, y1, x2, y2]);
        if (keptAnchors.length >= 2) break;
      }
    }

    final validCandidates = <_CandidateDocument>[];
    final weights = Float32List(numProtos);

    for (int c = 0; c < keptAnchors.length; c++) {
      final anchor = keptAnchors[c];
      final score = _getPredVal(4, anchor);
      final cx = _getPredVal(0, anchor);
      final cy = _getPredVal(1, anchor);
      final bw = _getPredVal(2, anchor);
      final bh = _getPredVal(3, anchor);

      final isPixelSpace = cx > 1.5 || cy > 1.5 || bw > 1.5 || bh > 1.5;
      final double scaleToProto = isPixelSpace ? (protoSize / inputSize) : protoSize.toDouble();

      final bx1 = (((cx - bw / 2.0) * scaleToProto).floor() - 3).clamp(minActiveX, maxActiveX - 1);
      final by1 = (((cy - bh / 2.0) * scaleToProto).floor() - 3).clamp(minActiveY, maxActiveY - 1);
      final bx2 = (((cx + bw / 2.0) * scaleToProto).ceil() + 3).clamp(minActiveX + 1, maxActiveX);
      final by2 = (((cy + bh / 2.0) * scaleToProto).ceil() + 3).clamp(minActiveY + 1, maxActiveY);

      for (int y = minActiveY; y < maxActiveY; y++) {
        _maskGrid[y].fillRange(minActiveX, maxActiveX, 0);
      }

      for (int k = 0; k < numProtos; k++) {
        weights[k] = _getPredVal(5 + k, anchor);
      }

      if (_isProtoNHWC) {
        // Flat NHWC [1, 160, 160, 32] dot product
        for (int y = by1; y < by2; y++) {
          final gridRow = _maskGrid[y];
          final yOffset = y * protoSize;
          for (int x = bx1; x < bx2; x++) {
            final baseIdx = (yOffset + x) * numProtos;
            double sum = 0.0;
            for (int k = 0; k < numProtos; k++) {
              sum += weights[k] * _outputProtosFlat[baseIdx + k];
            }
            gridRow[x] = sum > 0.0 ? 1 : 0;
          }
        }
      } else {
        // Flat NCHW [1, 32, 160, 160] dot product
        _maskAccFlat.fillRange(0, _maskAccFlat.length, 0.0);
        const planeStride = protoSize * protoSize;
        for (int k = 0; k < numProtos; k++) {
          final w = weights[k];
          if (w.abs() < 1e-4) continue;
          final kOffset = k * planeStride;
          for (int y = by1; y < by2; y++) {
            final rowOffset = y * protoSize;
            final protoRowStart = kOffset + rowOffset;
            for (int x = bx1; x < bx2; x++) {
              _maskAccFlat[rowOffset + x] += w * _outputProtosFlat[protoRowStart + x];
            }
          }
        }
        for (int y = by1; y < by2; y++) {
          final gridRow = _maskGrid[y];
          final rowOffset = y * protoSize;
          for (int x = bx1; x < bx2; x++) {
            gridRow[x] = _maskAccFlat[rowOffset + x] > 0.0 ? 1 : 0;
          }
        }
      }

      int truePixelCount = 0;
      final boundaryPoints = <math.Point<double>>[];

      for (int y = by1; y < by2; y++) {
        final row = _maskGrid[y];
        for (int x = bx1; x < bx2; x++) {
          if (row[x] == 1) {
            int neighbors = 0;
            if (y > minActiveY && _maskGrid[y - 1][x] == 1) neighbors++;
            if (y < maxActiveY - 1 && _maskGrid[y + 1][x] == 1) neighbors++;
            if (x > minActiveX && row[x - 1] == 1) neighbors++;
            if (x < maxActiveX - 1 && row[x + 1] == 1) neighbors++;

            if (neighbors >= 2) {
              truePixelCount++;
              if (neighbors < 4) {
                boundaryPoints.add(math.Point<double>(x.toDouble(), y.toDouble()));
              }
            }
          }
        }
      }

      if (boundaryPoints.length < 4) continue;

      final areaRatio = truePixelCount / activeArea160;
      if (areaRatio >= minDocumentArea && areaRatio <= maxDocumentArea) {
        validCandidates.add(_CandidateDocument(
          anchor: anchor,
          score: score,
          areaRatio: areaRatio,
          boundaryPoints: boundaryPoints,
        ));
      }
    }

    if (validCandidates.isEmpty) {
      return {
        'isValid': false,
        'confidence': _getPredVal(4, keptAnchors[0]),
        'areaRatio': 0.0,
      };
    }

    final primary = validCandidates.reduce((a, b) => a.areaRatio > b.areaRatio ? a : b);

    final strictCorners = _getStrict4Corners(
      primary.boundaryPoints,
      padX160,
      padY160,
      scaledW160,
      scaledH160,
    );

    if (strictCorners == null) {
      return {
        'isValid': false,
        'confidence': primary.score,
        'areaRatio': primary.areaRatio,
      };
    }

    return {
      'isValid': true,
      'confidence': primary.score,
      'areaRatio': primary.areaRatio,
      'corners': [
        strictCorners[0].x, strictCorners[0].y,
        strictCorners[1].x, strictCorners[1].y,
        strictCorners[2].x, strictCorners[2].y,
        strictCorners[3].x, strictCorners[3].y,
      ],
    };
  }

  List<CornerPoint>? _getStrict4Corners(
    List<math.Point<double>> boundaryPts,
    double padX160,
    double padY160,
    double scaledW160,
    double scaledH160,
  ) {
    final hull = _monotoneChainHull(boundaryPts);
    if (hull.length < 4) return null;

    double perimeter = 0.0;
    for (int i = 0; i < hull.length; i++) {
      final p1 = hull[i];
      final p2 = hull[(i + 1) % hull.length];
      perimeter += _hypot(p2.x - p1.x, p2.y - p1.y);
    }

    int splitA = 0;
    int splitB = hull.length ~/ 2;
    double maxDist = -1.0;
    for (int i = 0; i < hull.length; i++) {
      for (int j = i + 1; j < hull.length; j++) {
        final d = _hypot(hull[i].x - hull[j].x, hull[i].y - hull[j].y);
        if (d > maxDist) {
          maxDist = d;
          splitA = i;
          splitB = j;
        }
      }
    }

    final rotatedHull = <math.Point<double>>[
      ...hull.sublist(splitA),
      ...hull.sublist(0, splitA),
    ];
    final splitIdx = (splitB - splitA + hull.length) % hull.length;

    final firstHalf = rotatedHull.sublist(0, splitIdx + 1);
    final secondHalf = [...rotatedHull.sublist(splitIdx), rotatedHull.first];

    for (double factor = 0.015; factor <= 0.10; factor += 0.005) {
      final eps = factor * perimeter;
      final approx1 = _douglasPeucker(firstHalf, eps);
      final approx2 = _douglasPeucker(secondHalf, eps);

      if (approx1.length == 3 && approx2.length == 3) {
        final approx = [approx1[0], approx1[1], approx2[0], approx2[1]];
        final sorted = _sort4Corners(approx);
        final norm = sorted.map((p) {
          final nx = ((p.x - padX160) / scaledW160).clamp(0.0, 1.0);
          final ny = ((p.y - padY160) / scaledH160).clamp(0.0, 1.0);
          return CornerPoint(nx, ny);
        }).toList();

        if (_validateQuadrilateral(norm)) {
          return norm;
        }
      }
    }

    final fallbackSorted = _sort4Corners(hull);
    final fallbackNorm = fallbackSorted.map((p) {
      final nx = ((p.x - padX160) / scaledW160).clamp(0.0, 1.0);
      final ny = ((p.y - padY160) / scaledH160).clamp(0.0, 1.0);
      return CornerPoint(nx, ny);
    }).toList();

    if (_validateQuadrilateral(fallbackNorm)) {
      return fallbackNorm;
    }

    return null;
  }

  double _hypot(double dx, double dy) => math.sqrt(dx * dx + dy * dy);

  List<math.Point<double>> _monotoneChainHull(List<math.Point<double>> pts) {
    final sorted = pts.toSet().toList()
      ..sort((a, b) {
        final cmpX = a.x.compareTo(b.x);
        return cmpX != 0 ? cmpX : a.y.compareTo(b.y);
      });

    if (sorted.length <= 2) return sorted;

    double cross(math.Point<double> o, math.Point<double> a, math.Point<double> b) {
      return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
    }

    final lower = <math.Point<double>>[];
    for (final p in sorted) {
      while (lower.length >= 2 && cross(lower[lower.length - 2], lower[lower.length - 1], p) <= 0) {
        lower.removeLast();
      }
      lower.add(p);
    }

    final upper = <math.Point<double>>[];
    for (final p in sorted.reversed) {
      while (upper.length >= 2 && cross(upper[upper.length - 2], upper[upper.length - 1], p) <= 0) {
        upper.removeLast();
      }
      upper.add(p);
    }

    final hull = <math.Point<double>>[];
    for (int i = 0; i < lower.length - 1; i++) {
      hull.add(lower[i]);
    }
    for (int i = 0; i < upper.length - 1; i++) {
      hull.add(upper[i]);
    }
    return hull;
  }

  List<math.Point<double>> _douglasPeucker(List<math.Point<double>> pts, double eps) {
    if (pts.length <= 2) return pts;

    double dMax = 0.0;
    int index = 0;

    double pointLineDist(math.Point<double> pt, math.Point<double> l1, math.Point<double> l2) {
      final dx = l2.x - l1.x;
      final dy = l2.y - l1.y;
      final norm = _hypot(dx, dy);
      if (norm < 1e-6) return _hypot(pt.x - l1.x, pt.y - l1.y);
      return (dy * pt.x - dx * pt.y + l2.x * l1.y - l2.y * l1.x).abs() / norm;
    }

    for (int i = 1; i < pts.length - 1; i++) {
      final d = pointLineDist(pts[i], pts.first, pts.last);
      if (d > dMax) {
        index = i;
        dMax = d;
      }
    }

    if (dMax > eps) {
      final rec1 = _douglasPeucker(pts.sublist(0, index + 1), eps);
      final rec2 = _douglasPeucker(pts.sublist(index), eps);
      return [...rec1.sublist(0, rec1.length - 1), ...rec2];
    } else {
      return [pts.first, pts.last];
    }
  }

  List<math.Point<double>> _sort4Corners(List<math.Point<double>> pts) {
    math.Point<double> tl = pts[0];
    math.Point<double> br = pts[0];
    math.Point<double> tr = pts[0];
    math.Point<double> bl = pts[0];

    double minSum = double.infinity;
    double maxSum = -double.infinity;
    double minDiff = double.infinity;
    double maxDiff = -double.infinity;

    for (final p in pts) {
      final sum = p.x + p.y;
      final diff = p.y - p.x;

      if (sum < minSum) {
        minSum = sum;
        tl = p;
      }
      if (sum > maxSum) {
        maxSum = sum;
        br = p;
      }
      if (diff < minDiff) {
        minDiff = diff;
        tr = p;
      }
      if (diff > maxDiff) {
        maxDiff = diff;
        bl = p;
      }
    }

    return [tl, tr, br, bl];
  }

  bool _validateQuadrilateral(List<CornerPoint> pts) {
    if (pts.length != 4) return false;

    for (int i = 0; i < 4; i++) {
      for (int j = i + 1; j < 4; j++) {
        final d = _hypot(pts[i].x - pts[j].x, pts[i].y - pts[j].y);
        if (d < 0.08) return false;
      }
    }

    double crossProduct(CornerPoint a, CornerPoint b, CornerPoint c) {
      return (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x);
    }

    final cp1 = crossProduct(pts[0], pts[1], pts[2]);
    final cp2 = crossProduct(pts[1], pts[2], pts[3]);
    final cp3 = crossProduct(pts[2], pts[3], pts[0]);
    final cp4 = crossProduct(pts[3], pts[0], pts[1]);

    final isClockwise = cp1 > 0 && cp2 > 0 && cp3 > 0 && cp4 > 0;
    final isCounterClockwise = cp1 < 0 && cp2 < 0 && cp3 < 0 && cp4 < 0;
    if (!isClockwise && !isCounterClockwise) return false;

    double area = 0.0;
    for (int i = 0; i < 4; i++) {
      final j = (i + 1) % 4;
      area += pts[i].x * pts[j].y;
      area -= pts[j].x * pts[i].y;
    }
    area = (area.abs()) / 2.0;

    return area >= minDocumentArea && area <= maxDocumentArea;
  }
}
