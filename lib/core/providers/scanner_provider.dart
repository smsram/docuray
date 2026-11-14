import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import '../../models/models.dart';
import '../services/corner_detector_service.dart';
import '../services/jpeg_metadata.dart';
import '../services/scanner_diagnostics.dart';

enum ScannerState {
  searching,
  detected,
  holdSteady,
  ready,
  capturing,
  processing,
  failed,
  qualityProblem,
}

enum QualityIssue {
  moveCloser,
  holdSteady,
  reduceGlare,
  tooDark,
}

/// Explicit lifecycle states for document prediction validity
enum DocumentPredictionState {
  /// 1. Camera initialized, no prediction yet received from model
  initialNoPrediction,

  /// 2. Inference currently executing in background
  inferring,

  /// 3. Valid document prediction received from the model
  validDocument,

  /// 4. Completed inference with no valid document found
  noDocumentDetected,

  /// 5. Detection temporarily lost (within brief 250ms grace period to prevent flicker)
  detectionTemporarilyLost,

  /// 6. Camera stopped, paused, or scanner disposed
  stopped,
}

class ScannerProvider extends ChangeNotifier {
  final PaperCornerDetector _cornerDetector = PaperCornerDetector();

  /// MUST BE FALSE to use Flutter CameraPreview + Dart PaperCornerDetector (best.tflite)
  static const bool useNativePlatformView = false;

  MethodChannel? _nativeChannel;
  CameraController? _cameraController;
  List<CameraDescription> _availableCameras = [];
  bool _isCameraReady = false;
  bool _isInitializing = false;
  bool _permissionDenied = false;
  bool _isStreaming = false;
  bool _isCameraActive = false;
  bool _isDisposed = false;

  ScannerState _state = ScannerState.searching;
  QualityIssue _qualityIssue = QualityIssue.moveCloser;

  String _flashMode = 'off';
  String _captureMode = 'Auto';
  String _captureType = 'Document';

  // Prediction Lifecycle State Management
  DocumentPredictionState _predictionState = DocumentPredictionState.initialNoPrediction;
  bool _hasValidPrediction = false;
  bool _hasEverReceivedValidPrediction = false;
  DateTime? _lastValidPredictionTime;

  bool _isProcessingFrame = false;
  bool _isDetecting = false;
  bool _isCapturing = false;
  bool _showDiagnostics = false;
  int _missedFramesCount = 0;
  Map<String, dynamic>? _diagnosticMetrics;
  DateTime? _readyStartTime;

  CameraImage? _pendingFrame;
  List<Offset>? _detectedCorners;

  /// Isolated ValueNotifier for corner overlay updates (avoids full-screen rebuilds on every prediction)
  final ValueNotifier<List<Offset>?> cornersNotifier = ValueNotifier<List<Offset>?>(null);
  final ValueNotifier<DocumentPredictionState> predictionStateNotifier =
      ValueNotifier<DocumentPredictionState>(DocumentPredictionState.initialNoPrediction);

  /// Internal diagnostic performance tracker
  final ScannerDiagnosticsTracker _diagnostics = ScannerDiagnosticsTracker();

  void Function(DocumentPage capturedPage)? onAutoCaptured;

  CameraController? get cameraController => _cameraController;
  bool get isCameraReady => _isCameraReady;
  bool get isInitializing => _isInitializing;
  bool get permissionDenied => _permissionDenied;
  ScannerState get state => _state;
  QualityIssue get qualityIssue => _qualityIssue;
  String get flashMode => _flashMode;
  bool get isFlashOn => _flashMode == 'on';
  String get captureMode => _captureMode;
  bool get isAutoCapture => _captureMode == 'Auto';
  String get captureType => _captureType;
  String get scanMode => _captureType;
  DocumentPredictionState get predictionState => _predictionState;
  bool get hasValidPrediction => _hasValidPrediction;
  List<Offset> get detectedCorners => _detectedCorners ?? const [];
  bool get isCapturing => _isCapturing;
  bool get isDetecting => _isDetecting;
  bool get showDiagnostics => _showDiagnostics;
  Map<String, dynamic>? get diagnosticMetrics => _diagnosticMetrics;
  ScannerPerformanceMetrics get performanceMetrics => _diagnostics.getMetrics();

  String get stateMessage {
    if (!isAutoCapture) {
      if (_isCapturing) return 'Capturing...';
      return 'Manual mode: Tap shutter to capture';
    }

    switch (_state) {
      case ScannerState.searching:
        return _captureType == 'ID Card'
            ? 'Align ID card inside guide'
            : 'Move camera over document';
      case ScannerState.detected:
        return 'Document detected';
      case ScannerState.holdSteady:
        return 'Hold steady';
      case ScannerState.ready:
        return 'Ready';
      case ScannerState.capturing:
        return 'Capturing...';
      case ScannerState.processing:
        return 'Processing scan...';
      case ScannerState.failed:
        return 'Document not detected';
      case ScannerState.qualityProblem:
        switch (_qualityIssue) {
          case QualityIssue.moveCloser:
            return 'Move closer to the document';
          case QualityIssue.holdSteady:
            return 'Hold steady';
          case QualityIssue.reduceGlare:
            return 'Reduce glare on paper surface';
          case QualityIssue.tooDark:
            return 'Move to better lighting';
        }
    }
  }

  void onNativeViewCreated(int id) {
    if (!useNativePlatformView) return;
    _nativeChannel = MethodChannel('com.docuray/scanner_view_$id');
    _nativeChannel!.setMethodCallHandler(_handleNativeCall);
    _nativeChannel!.invokeMethod('setAutoMode', {'isAuto': isAutoCapture});
    _nativeChannel!.invokeMethod('setCaptureType', {'type': _captureType});
    _nativeChannel!.invokeMethod('setFlashMode', {'mode': _flashMode});
    _isCameraReady = true;
    notifyListeners();
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onStatusChanged':
        final status = call.arguments['status'] as String?;
        if (status != null) {
          switch (status) {
            case 'searching':
              _state = ScannerState.searching;
              break;
            case 'detected':
              _state = ScannerState.detected;
              break;
            case 'holdSteady':
              _state = ScannerState.holdSteady;
              break;
            case 'ready':
              _state = ScannerState.ready;
              break;
            case 'manual':
              _state = ScannerState.searching;
              break;
          }
          notifyListeners();
        }
        break;
      case 'onCornersDetected':
        final rawCorners = (call.arguments['corners'] as List?)
            ?.map((e) => (e as num).toDouble())
            .toList();
        if (rawCorners != null && rawCorners.length >= 8) {
          _detectedCorners = [
            Offset(rawCorners[0], rawCorners[1]),
            Offset(rawCorners[2], rawCorners[3]),
            Offset(rawCorners[4], rawCorners[5]),
            Offset(rawCorners[6], rawCorners[7]),
          ];
          notifyListeners();
        }
        break;
      case 'onAutoCapture':
        _isCapturing = true;
        _state = ScannerState.capturing;
        notifyListeners();
        break;
      case 'onMetricsUpdate':
        _diagnosticMetrics = Map<String, dynamic>.from(call.arguments as Map);
        if (_showDiagnostics) {
          notifyListeners();
        }
        break;
      case 'onPhotoCaptured':
        final map = Map<String, dynamic>.from(call.arguments as Map);
        _handleCapturedResult(map);
        break;
    }
    return null;
  }

  void toggleDiagnostics() {
    _showDiagnostics = !_showDiagnostics;
    _nativeChannel?.invokeMethod('setDiagnosticsEnabled', {'enabled': _showDiagnostics});
    notifyListeners();
  }

  void _handleCapturedResult(Map<String, dynamic> data) {
    final rawPath = data['rawPath'] as String?;
    final croppedPath = data['croppedPath'] as String?;
    final rawCorners = (data['corners'] as List?)?.map((e) => (e as num).toDouble()).toList() ?? [];

    if (rawPath == null) {
      _isCapturing = false;
      _state = ScannerState.searching;
      notifyListeners();
      return;
    }

    List<CornerPoint> finalCorners;
    if (rawCorners.length >= 8) {
      finalCorners = [
        CornerPoint(rawCorners[0], rawCorners[1]),
        CornerPoint(rawCorners[2], rawCorners[3]),
        CornerPoint(rawCorners[4], rawCorners[5]),
        CornerPoint(rawCorners[6], rawCorners[7]),
      ];
    } else {
      finalCorners = const [
        CornerPoint(0.05, 0.05),
        CornerPoint(0.95, 0.05),
        CornerPoint(0.95, 0.95),
        CornerPoint(0.05, 0.95),
      ];
    }

    final page = DocumentPage(
      id: 'page_${DateTime.now().millisecondsSinceEpoch}',
      pageNumber: 1,
      originalImagePath: rawPath,
      processedImagePath: (croppedPath != null && croppedPath != rawPath) ? croppedPath : null,
      corners: finalCorners,
      autoDetectedCorners: isAutoCapture ? finalCorners : null,
      filterType: 'auto',
    );

    _isCapturing = false;
    _state = ScannerState.ready;
    notifyListeners();

    onAutoCaptured?.call(page);
  }

  Future<void> initializeCamera() async {
    if (_isInitializing || _isCameraReady) return;
    _isInitializing = true;
    notifyListeners();

    try {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        _permissionDenied = true;
        _isInitializing = false;
        notifyListeners();
        return;
      }

      _permissionDenied = false;

      if (useNativePlatformView) {
        _isCameraReady = true;
        _isInitializing = false;
        notifyListeners();
        return;
      }

      await _cornerDetector.initialize();

      if (_availableCameras.isEmpty) {
        _availableCameras = await availableCameras();
      }

      if (_availableCameras.isEmpty) {
        _isInitializing = false;
        notifyListeners();
        return;
      }

      final rearCamera = _availableCameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _availableCameras.first,
      );

      final controller = CameraController(
        rearCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.yuv420
            : ImageFormatGroup.bgra8888,
      );

      await controller.initialize();
      _cameraController = controller;
      _isCameraReady = true;
      _isInitializing = false;

      await _startImageStream();
      notifyListeners();
    } catch (e) {
      debugPrint('[DocuRay] Camera initialization failed: $e');
      _isCameraReady = false;
      _isInitializing = false;
      notifyListeners();
    }
  }

  Future<void> _startImageStream() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized || _isStreaming) {
      return;
    }

    try {
      _isStreaming = true;
      _isCameraActive = true;
      await _cameraController!.startImageStream((CameraImage image) {
        _onCameraFrame(image);
      });
    } catch (e) {
      debugPrint('[DocuRay] startImageStream error: $e');
      _isStreaming = false;
      _isCameraActive = false;
    }
  }

  /// High-throughput, latest-frame-only stream receiver
  void _onCameraFrame(CameraImage image) {
    if (_isDisposed) return;
    _diagnostics.recordCameraFrame();

    // Inference should continue ONLY when the camera is active and Auto mode is enabled
    if (!isAutoCapture || _isCapturing || !_isCameraActive) {
      return;
    }

    if (_isProcessingFrame) {
      // Discard previous pending frame (latest-frame-only policy)
      if (_pendingFrame != null) {
        _diagnostics.recordDroppedFrame();
      }
      _pendingFrame = image;
      return;
    }

    _pendingFrame = image;
    _scheduleNextInference();
  }

  void _scheduleNextInference() {
    if (_isDisposed || _isProcessingFrame || _pendingFrame == null || !isAutoCapture || _isCapturing || !_isCameraActive) {
      return;
    }

    final frameToProcess = _pendingFrame!;
    _pendingFrame = null;
    _isProcessingFrame = true;
    _isDetecting = true;

    _diagnostics.recordSubmittedFrame();

    _runInferenceOnFrame(frameToProcess).then((_) {
      _isProcessingFrame = false;
      _isDetecting = false;

      // Immediately process the freshest available frame that arrived during inference
      if (!_isDisposed && _pendingFrame != null && isAutoCapture && !_isCapturing && _isCameraActive) {
        _scheduleNextInference();
      }
    });
  }

  Future<void> _runInferenceOnFrame(CameraImage image) async {
    try {
      final sensorOrientation = _cameraController?.description.sensorOrientation ?? 90;
      final result = await _cornerDetector.detectCornersFromCameraImage(
        image,
        sensorOrientation: sensorOrientation,
      );

      if (_isDisposed || !_isCameraActive || !isAutoCapture) return;

      _diagnostics.recordCompletedPrediction(result.metrics);
      if (result.metrics != null) {
        _diagnosticMetrics = result.metrics;
      }

      final oldState = _state;

      if (result.isValid) {
        _missedFramesCount = 0;
        _hasValidPrediction = true;
        _hasEverReceivedValidPrediction = true;
        _lastValidPredictionTime = DateTime.now();
        _predictionState = DocumentPredictionState.validDocument;

        _detectedCorners = result.corners.map((c) => Offset(c.x, c.y)).toList();

        // Update isolated value notifiers (avoids rebuilding complete scanning screen)
        cornersNotifier.value = _detectedCorners;
        predictionStateNotifier.value = DocumentPredictionState.validDocument;

        final stableFrames = _cornerDetector.consecutiveStableFrames;

        if (stableFrames >= 6) {
          _state = ScannerState.ready;
          _readyStartTime ??= DateTime.now();

          if (isAutoCapture &&
              !_isCapturing &&
              DateTime.now().difference(_readyStartTime!).inMilliseconds >= 500) {
            _triggerAutoCapture();
          }
        } else if (stableFrames >= 2) {
          _state = ScannerState.holdSteady;
          _readyStartTime = null;
        } else {
          _state = ScannerState.detected;
          _readyStartTime = null;
        }
      } else {
        _missedFramesCount++;
        _readyStartTime = null;

        final now = DateTime.now();
        final msSinceValid = _lastValidPredictionTime != null
            ? now.difference(_lastValidPredictionTime!).inMilliseconds
            : 9999;

        if (!_hasEverReceivedValidPrediction) {
          _predictionState = DocumentPredictionState.initialNoPrediction;
          _hasValidPrediction = false;
          cornersNotifier.value = null;
          predictionStateNotifier.value = _predictionState;
        } else if (msSinceValid <= 250 && _missedFramesCount <= 2) {
          // Grace period: prevent flickering from single dropped/missed detection
          _predictionState = DocumentPredictionState.detectionTemporarilyLost;
          predictionStateNotifier.value = _predictionState;
        } else {
          // Genuine loss: hide indicators and clear stabilization
          _predictionState = DocumentPredictionState.noDocumentDetected;
          _hasValidPrediction = false;
          _cornerDetector.resetStabilization();
          cornersNotifier.value = null;
          predictionStateNotifier.value = _predictionState;

          if (_missedFramesCount >= 3) {
            _state = ScannerState.searching;
          }
          if (_missedFramesCount > 6) {
            _detectedCorners = null;
          }
        }
      }

      // ONLY rebuild scanning screen UI when the high-level scanner state actually changes!
      if (_state != oldState) {
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[DocuRay] Live frame processing error: $e');
    }
  }

  void _triggerAutoCapture() async {
    final page = await captureDocument();
    if (page != null && onAutoCaptured != null) {
      onAutoCaptured!(page);
    }
  }

  Future<DocumentPage?> captureDocument() async {
    if (_isCapturing) return null;

    if (useNativePlatformView && _nativeChannel != null) {
      _isCapturing = true;
      _state = ScannerState.capturing;
      notifyListeners();

      try {
        final res = await _nativeChannel!.invokeMapMethod<String, dynamic>('takePhoto');
        if (res != null) {
          final rawPath = res['rawPath'] as String;
          final croppedPath = res['croppedPath'] as String;
          final rawCorners = (res['corners'] as List?)?.map((e) => (e as num).toDouble()).toList() ?? [];

          List<CornerPoint> finalCorners;
          if (rawCorners.length >= 8) {
            finalCorners = [
              CornerPoint(rawCorners[0], rawCorners[1]),
              CornerPoint(rawCorners[2], rawCorners[3]),
              CornerPoint(rawCorners[4], rawCorners[5]),
              CornerPoint(rawCorners[6], rawCorners[7]),
            ];
          } else {
            finalCorners = const [
              CornerPoint(0.05, 0.05),
              CornerPoint(0.95, 0.05),
              CornerPoint(0.95, 0.95),
              CornerPoint(0.05, 0.95),
            ];
          }

          return DocumentPage(
            id: 'page_${DateTime.now().millisecondsSinceEpoch}',
            pageNumber: 1,
            originalImagePath: rawPath,
            processedImagePath: (croppedPath != rawPath) ? croppedPath : null,
            corners: finalCorners,
            autoDetectedCorners: isAutoCapture ? finalCorners : null,
            filterType: 'auto',
          );
        }
      } catch (e) {
        debugPrint('[DocuRay] Native captureDocument error: $e');
      } finally {
        _isCapturing = false;
        _state = ScannerState.searching;
        notifyListeners();
      }
      return null;
    }

    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return null;
    }

    // Retrieve live detected corners as the ground truth BEFORE changing state
    final bool hadDetection = _hasValidPrediction &&
        _detectedCorners != null &&
        _detectedCorners!.length == 4 &&
        (_state == ScannerState.ready ||
            _state == ScannerState.holdSteady ||
            _state == ScannerState.detected);
    final List<Offset>? capturedCorners =
        hadDetection ? List<Offset>.from(_detectedCorners!) : null;

    _isCapturing = true;
    _state = ScannerState.capturing;
    notifyListeners();

    try {
      if (_isStreaming) {
        try {
          await _cameraController!.stopImageStream();
          _isStreaming = false;
        } catch (_) {}
      }

      final xFile = await _cameraController!.takePicture();

      _state = ScannerState.processing;
      notifyListeners();

      // Extract photo dimensions and EXIF orientation without decoding full image
      final jpegInfo = await JpegMetadata.fromFile(File(xFile.path));

      // Calculate preview aspect ratio
      final previewSize = _cameraController!.value.previewSize;
      final sensorOrientation = _cameraController!.description.sensorOrientation;
      final isRotated90 = sensorOrientation == 90 || sensorOrientation == 270;
      final double prevW = isRotated90
          ? (previewSize?.height ?? 720.0)
          : (previewSize?.width ?? 1280.0);
      final double prevH = isRotated90
          ? (previewSize?.width ?? 1280.0)
          : (previewSize?.height ?? 720.0);
      final double prevAspect = prevW / prevH;

      double photoAspect = prevAspect;
      if (jpegInfo != null && jpegInfo.uprightWidth > 0 && jpegInfo.uprightHeight > 0) {
        photoAspect = jpegInfo.uprightAspectRatio;
      } else {
        try {
          final bytes = await File(xFile.path).readAsBytes();
          final decoded = img.decodeImage(bytes);
          if (decoded != null) {
            final oriented = img.bakeOrientation(decoded);
            if (oriented.width > 0 && oriented.height > 0) {
              photoAspect = oriented.width / oriented.height;
            }
          }
        } catch (_) {}
      }

      final bool isFront = _cameraController!.description.lensDirection == CameraLensDirection.front;

      List<CornerPoint> finalCorners;
      if (hadDetection && capturedCorners != null && capturedCorners.length == 4) {
        var cornersToMap = capturedCorners;

        // Front camera mirroring: flip horizontally and preserve [TL, TR, BR, BL] order
        if (isFront) {
          cornersToMap = [
            Offset(1.0 - cornersToMap[1].dx, cornersToMap[1].dy),
            Offset(1.0 - cornersToMap[0].dx, cornersToMap[0].dy),
            Offset(1.0 - cornersToMap[3].dx, cornersToMap[3].dy),
            Offset(1.0 - cornersToMap[2].dx, cornersToMap[2].dy),
          ];
        }

        finalCorners = cornersToMap.map((o) {
          double nx = o.dx;
          double ny = o.dy;

          // Adjust for aspect ratio difference if preview is cropped relative to sensor
          if ((prevAspect - photoAspect).abs() > 0.005) {
            if (prevAspect < photoAspect) {
              // Preview is narrower than photo (cropped horizontally by CameraX)
              nx = 0.5 + (nx - 0.5) * (prevAspect / photoAspect);
            } else {
              // Preview is wider than photo (cropped vertically by CameraX)
              ny = 0.5 + (ny - 0.5) * (photoAspect / prevAspect);
            }
          }

          return CornerPoint(nx.clamp(0.0, 1.0), ny.clamp(0.0, 1.0));
        }).toList();
      } else {
        // Fallback to full image bounds for manual or undetected captures
        finalCorners = const [
          CornerPoint(0.0, 0.0),
          CornerPoint(1.0, 0.0),
          CornerPoint(1.0, 1.0),
          CornerPoint(0.0, 1.0),
        ];
      }

      final page = DocumentPage(
        id: 'page_${DateTime.now().millisecondsSinceEpoch}',
        pageNumber: 1,
        originalImagePath: xFile.path,
        corners: finalCorners,
        autoDetectedCorners: hadDetection ? finalCorners : null,
        filterType: 'auto',
      );

      _state = ScannerState.ready;
      _isCapturing = false;
      notifyListeners();

      return page;
    } catch (e) {
      debugPrint('[DocuRay] Capture error: $e');
      _isCapturing = false;
      _state = ScannerState.searching;
      await _startImageStream();
      notifyListeners();
      return null;
    }
  }

  bool _isImporting = false;

  Future<List<DocumentPage>> importFromGallery() async {
    if (_isImporting) return [];
    _isImporting = true;
    _state = ScannerState.processing;
    notifyListeners();

    // Snapshot current capture mode before picker opens
    final bool shouldRunDetection = isAutoCapture;

    try {
      final picker = ImagePicker();
      final pickedFiles = await picker.pickMultiImage();
      if (pickedFiles.isEmpty) {
        _state = ScannerState.searching;
        notifyListeners();
        return [];
      }

      final pages = <DocumentPage>[];

      for (int i = 0; i < pickedFiles.length; i++) {
        final file = pickedFiles[i];
        DetectionResult? detection;

        // Apply corner detection for all selected images ONLY if Auto mode was active
        if (shouldRunDetection) {
          try {
            detection = await _cornerDetector
                .detectCornersFromPath(file.path)
                .timeout(const Duration(seconds: 4));
          } catch (e) {
            debugPrint('[DocuRay] Corner detection timed out or failed for ${file.path}: $e');
          }
        }

        final bool hasValidDoc = shouldRunDetection && detection != null && detection.isValid;
        final List<CornerPoint> corners = hasValidDoc
            ? detection.corners
            : const [
                CornerPoint(0.0, 0.0),
                CornerPoint(1.0, 0.0),
                CornerPoint(1.0, 1.0),
                CornerPoint(0.0, 1.0),
              ];

        pages.add(
          DocumentPage(
            id: 'page_${DateTime.now().millisecondsSinceEpoch}_$i',
            pageNumber: i + 1,
            originalImagePath: file.path,
            corners: corners,
            autoDetectedCorners: hasValidDoc ? corners : null,
            filterType: 'auto',
          ),
        );
      }

      _state = ScannerState.ready;
      notifyListeners();
      return pages;
    } on PlatformException catch (e) {
      debugPrint('[DocuRay] Image picker PlatformException: $e');
      _state = ScannerState.searching;
      notifyListeners();
      return [];
    } catch (e) {
      debugPrint('[DocuRay] importFromGallery error: $e');
      _state = ScannerState.searching;
      notifyListeners();
      return [];
    } finally {
      _isImporting = false;
    }
  }

  Future<void> resumeCamera() async {
    _isCameraActive = true;
    _isCapturing = false;
    _hasValidPrediction = false;
    _hasEverReceivedValidPrediction = false;
    _detectedCorners = null;
    _lastValidPredictionTime = null;
    _missedFramesCount = 0;
    _predictionState = isAutoCapture
        ? DocumentPredictionState.initialNoPrediction
        : DocumentPredictionState.stopped;

    cornersNotifier.value = null;
    predictionStateNotifier.value = _predictionState;
    _diagnostics.reset();
    _cornerDetector.resetStabilization();

    if (useNativePlatformView && _nativeChannel != null) {
      try {
        await _nativeChannel!.invokeMethod('resumeScanner');
      } catch (e) {
        debugPrint('[DocuRay] Native resumeScanner error: $e');
      }
    }
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      try {
        await _cameraController!.resumePreview();
      } catch (_) {}
      if (!_isStreaming) {
        await _startImageStream();
      }
    }
    _state = ScannerState.searching;
    notifyListeners();
  }

  Future<void> pauseCamera() async {
    _isCameraActive = false;
    _pendingFrame = null;
    _isProcessingFrame = false;
    _isDetecting = false;
    _isCapturing = false;
    _readyStartTime = null;
    _predictionState = DocumentPredictionState.stopped;

    cornersNotifier.value = null;
    predictionStateNotifier.value = DocumentPredictionState.stopped;
    _cornerDetector.resetStabilization();

    if (useNativePlatformView && _nativeChannel != null) {
      try {
        await _nativeChannel!.invokeMethod('pauseScanner');
      } catch (e) {
        debugPrint('[DocuRay] Native pauseScanner error: $e');
      }
    }
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      if (_isStreaming) {
        try {
          await _cameraController!.stopImageStream();
        } catch (_) {}
        _isStreaming = false;
      }
      try {
        await _cameraController!.pausePreview();
      } catch (_) {}
    }
    _state = ScannerState.searching;
    notifyListeners();
  }

  Future<void> stopAndDisposeCamera() async {
    await pauseCamera();
    if (_cameraController != null) {
      try {
        await _cameraController!.dispose();
      } catch (_) {}
      _cameraController = null;
    }
    _isCameraReady = false;
    _isInitializing = false;
    _isStreaming = false;
    _isDetecting = false;
    notifyListeners();
  }

  void cycleFlash() async {
    if (_flashMode == 'off') {
      _flashMode = 'auto';
    } else if (_flashMode == 'auto') {
      _flashMode = 'on';
    } else {
      _flashMode = 'off';
    }

    if (useNativePlatformView && _nativeChannel != null) {
      try {
        await _nativeChannel!.invokeMethod('setFlashMode', {'mode': _flashMode});
      } catch (e) {
        debugPrint('[DocuRay] Native flash set error: $e');
      }
    } else if (_cameraController != null && _cameraController!.value.isInitialized) {
      try {
        final mode = _flashMode == 'on'
            ? FlashMode.torch
            : (_flashMode == 'auto' ? FlashMode.auto : FlashMode.off);
        await _cameraController!.setFlashMode(mode);
      } catch (e) {
        debugPrint('[DocuRay] Flash set error: $e');
      }
    }
    notifyListeners();
  }

  void toggleFlash() => cycleFlash();

  void setCaptureMode(String mode) {
    if (_captureMode == mode) return;
    _captureMode = mode;
    _readyStartTime = null;

    if (!isAutoCapture) {
      // Manual mode: cancel queued frames, clear indicators, pause model inference
      _pendingFrame = null;
      _hasValidPrediction = false;
      _detectedCorners = null;
      cornersNotifier.value = null;
      _predictionState = DocumentPredictionState.stopped;
      predictionStateNotifier.value = DocumentPredictionState.stopped;
      _state = ScannerState.searching;
      _cornerDetector.resetStabilization();
      if (useNativePlatformView && _nativeChannel != null) {
        try {
          _nativeChannel!.invokeMethod('setAutoMode', {'isAuto': false});
        } catch (_) {}
      }
    } else {
      // Auto mode: start fresh with clean detection state
      _hasValidPrediction = false;
      _detectedCorners = null;
      cornersNotifier.value = null;
      _predictionState = DocumentPredictionState.initialNoPrediction;
      predictionStateNotifier.value = DocumentPredictionState.initialNoPrediction;
      _state = ScannerState.searching;
      _cornerDetector.resetStabilization();
      if (useNativePlatformView && _nativeChannel != null) {
        try {
          _nativeChannel!.invokeMethod('setAutoMode', {'isAuto': true});
        } catch (_) {}
      }
    }
    notifyListeners();
  }

  void toggleAutoCapture() {
    setCaptureMode(isAutoCapture ? 'Manual' : 'Auto');
  }

  void setCaptureType(String type) {
    _captureType = type;
    if (useNativePlatformView && _nativeChannel != null) {
      try {
        _nativeChannel!.invokeMethod('setCaptureType', {'type': _captureType});
      } catch (_) {}
    }
    notifyListeners();
  }

  void setScanMode(String mode) => setCaptureType(mode);

  void setState(ScannerState newState) {
    _state = newState;
    notifyListeners();
  }

  void setQualityIssue(QualityIssue issue) {
    _qualityIssue = issue;
    _state = ScannerState.qualityProblem;
    notifyListeners();
  }

  void updateCorners(List<Offset> corners) {
    _detectedCorners = corners;
    notifyListeners();
  }

  void disposeCamera() {
    _isDisposed = true;
    _isCameraActive = false;
    _pendingFrame = null;
    if (_nativeChannel != null) {
      _nativeChannel!.setMethodCallHandler(null);
      _nativeChannel = null;
    }
    _isStreaming = false;
    _cameraController?.dispose();
    _cameraController = null;
    _isCameraReady = false;
    _cornerDetector.dispose();
  }

  @override
  void dispose() {
    disposeCamera();
    cornersNotifier.dispose();
    predictionStateNotifier.dispose();
    super.dispose();
  }
}
