import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../models/models.dart';
import '../services/corner_detector_service.dart';
import '../services/jpeg_metadata.dart';

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

  ScannerState _state = ScannerState.searching;
  QualityIssue _qualityIssue = QualityIssue.moveCloser;

  String _flashMode = 'off';
  String _captureMode = 'Auto';
  String _captureType = 'Document';

  bool _isDetecting = false;
  bool _isCapturing = false;
  bool _showDiagnostics = false;
  int _missedFramesCount = 0;
  Map<String, dynamic>? _diagnosticMetrics;
  DateTime _lastInferenceTime = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _readyStartTime;

  List<Offset> _detectedCorners = [
    const Offset(0.08, 0.08),
    const Offset(0.92, 0.08),
    const Offset(0.92, 0.92),
    const Offset(0.08, 0.92),
  ];

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
  List<Offset> get detectedCorners => _detectedCorners;
  bool get isCapturing => _isCapturing;
  bool get showDiagnostics => _showDiagnostics;
  Map<String, dynamic>? get diagnosticMetrics => _diagnosticMetrics;

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
      await _cameraController!.startImageStream((CameraImage image) {
        _processPreviewFrame(image);
      });
    } catch (e) {
      debugPrint('[DocuRay] startImageStream error: $e');
      _isStreaming = false;
    }
  }

  void _processPreviewFrame(CameraImage image) async {
    final now = DateTime.now();
    if (_isDetecting || _isCapturing || now.difference(_lastInferenceTime).inMilliseconds < 35) {
      return;
    }

    _isDetecting = true;
    _lastInferenceTime = now;

    try {
      final sensorOrientation = _cameraController?.description.sensorOrientation ?? 90;
      final result = await _cornerDetector.detectCornersFromCameraImage(
        image,
        sensorOrientation: sensorOrientation,
      );

      if (result.metrics != null) {
        _diagnosticMetrics = result.metrics;
      }

      if (result.isValid) {
        _missedFramesCount = 0;
        _detectedCorners = result.corners.map((c) => Offset(c.x, c.y)).toList();

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
        if (_missedFramesCount >= 3) {
          _state = ScannerState.searching;
          _cornerDetector.resetStabilization();
        }
      }

      notifyListeners();
    } catch (e) {
      debugPrint('[DocuRay] Live frame processing error: $e');
    } finally {
      _isDetecting = false;
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

      // Retrieve live detected corners as the ground truth
      final capturedCorners = List<Offset>.from(_detectedCorners);
      final bool wasDetected = _state == ScannerState.ready ||
          _state == ScannerState.holdSteady ||
          _state == ScannerState.detected;

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
      final double photoAspect = jpegInfo?.uprightAspectRatio ?? prevAspect;

      final bool isFront = _cameraController!.description.lensDirection == CameraLensDirection.front;

      // Transfer the exact four detected corner coordinates from scan screen to photo coordinates
      final List<CornerPoint> finalCorners = capturedCorners.map((o) {
        double nx = o.dx;
        double ny = o.dy;

        // Front camera mirroring
        if (isFront) {
          nx = 1.0 - nx;
        }

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

      final page = DocumentPage(
        id: 'page_${DateTime.now().millisecondsSinceEpoch}',
        pageNumber: 1,
        originalImagePath: xFile.path,
        corners: finalCorners,
        autoDetectedCorners: (wasDetected || isAutoCapture) ? finalCorners : null,
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
        try {
          detection = await _cornerDetector
              .detectCornersFromPath(file.path)
              .timeout(const Duration(seconds: 4));
        } catch (e) {
          debugPrint('[DocuRay] Corner detection timed out or failed for ${file.path}: $e');
        }

        List<CornerPoint> corners;
        if (detection != null && detection.isValid && !detection.isTightlyFramed) {
          corners = detection.corners;
        } else {
          corners = const [
            CornerPoint(0.0, 0.0),
            CornerPoint(1.0, 0.0),
            CornerPoint(1.0, 1.0),
            CornerPoint(0.0, 1.0),
          ];
        }

        pages.add(
          DocumentPage(
            id: 'page_${DateTime.now().millisecondsSinceEpoch}_$i',
            pageNumber: i + 1,
            originalImagePath: file.path,
            corners: corners,
            autoDetectedCorners: (detection != null && detection.isValid) ? corners : null,
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
        _cornerDetector.resetStabilization();
        await _startImageStream();
      }
    }
    _state = ScannerState.searching;
    _isCapturing = false;
    notifyListeners();
  }

  Future<void> pauseCamera() async {
    _isDetecting = false;
    _isCapturing = false;
    _readyStartTime = null;

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
    _cornerDetector.resetStabilization();
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

    if (_captureMode == 'Manual') {
      _detectedCorners = const [
        Offset(0.05, 0.05),
        Offset(0.95, 0.05),
        Offset(0.95, 0.95),
        Offset(0.05, 0.95),
      ];
      _state = ScannerState.searching;
      _cornerDetector.resetStabilization();
      if (useNativePlatformView && _nativeChannel != null) {
        try {
          _nativeChannel!.invokeMethod('setAutoMode', {'isAuto': false});
        } catch (_) {}
      }
    } else {
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
    super.dispose();
  }
}
