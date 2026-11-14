import 'dart:collection';
import 'package:flutter/foundation.dart';

/// Performance metrics for the camera-to-prediction pipeline.
class ScannerPerformanceMetrics {
  final double cameraFps;
  final double submittedFps;
  final double completedFps;
  final int droppedCount;
  final double droppedFps;
  final double prepMs;
  final double inferenceMs;
  final double postprocessMs;
  final double totalLatencyMs;
  final String backend;
  final bool hasDocument;
  final double confidence;

  const ScannerPerformanceMetrics({
    required this.cameraFps,
    required this.submittedFps,
    required this.completedFps,
    required this.droppedCount,
    required this.droppedFps,
    required this.prepMs,
    required this.inferenceMs,
    required this.postprocessMs,
    required this.totalLatencyMs,
    required this.backend,
    required this.hasDocument,
    required this.confidence,
  });

  static const ScannerPerformanceMetrics empty = ScannerPerformanceMetrics(
    cameraFps: 0.0,
    submittedFps: 0.0,
    completedFps: 0.0,
    droppedCount: 0,
    droppedFps: 0.0,
    prepMs: 0.0,
    inferenceMs: 0.0,
    postprocessMs: 0.0,
    totalLatencyMs: 0.0,
    backend: 'N/A',
    hasDocument: false,
    confidence: 0.0,
  );

  @override
  String toString() {
    return 'Camera: ${cameraFps.toStringAsFixed(1)} fps | '
        'Sub: ${submittedFps.toStringAsFixed(1)} fps | '
        'Pred: ${completedFps.toStringAsFixed(1)} fps | '
        'Drop: ${droppedFps.toStringAsFixed(1)} fps | '
        'Prep: ${prepMs.toStringAsFixed(1)}ms | '
        'Infer: ${inferenceMs.toStringAsFixed(1)}ms | '
        'Post: ${postprocessMs.toStringAsFixed(1)}ms | '
        'Latency: ${totalLatencyMs.toStringAsFixed(1)}ms | '
        'Backend: $backend';
  }
}

/// Rolling-window performance tracker for camera stream and model inference.
class ScannerDiagnosticsTracker {
  static const int _windowDurationMs = 1000;

  final Queue<int> _cameraFrameTimestamps = Queue<int>();
  final Queue<int> _submittedFrameTimestamps = Queue<int>();
  final Queue<int> _completedPredictionTimestamps = Queue<int>();
  final Queue<int> _droppedFrameTimestamps = Queue<int>();

  final List<double> _recentPrepTimes = [];
  final List<double> _recentInferTimes = [];
  final List<double> _recentPostTimes = [];
  final List<double> _recentTotalTimes = [];

  String _lastBackend = 'CPU';
  bool _lastHasDoc = false;
  double _lastConf = 0.0;
  int _totalDroppedAllTime = 0;

  DateTime _lastLogTime = DateTime.fromMillisecondsSinceEpoch(0);

  void recordCameraFrame() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _cameraFrameTimestamps.add(now);
    _purgeOld(now);
  }

  void recordSubmittedFrame() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _submittedFrameTimestamps.add(now);
    _purgeOld(now);
  }

  void recordDroppedFrame() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _droppedFrameTimestamps.add(now);
    _totalDroppedAllTime++;
    _purgeOld(now);
  }

  void recordCompletedPrediction(Map<String, dynamic>? metrics) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _completedPredictionTimestamps.add(now);

    if (metrics != null) {
      final prep = (metrics['prepMs'] as num?)?.toDouble() ?? 0.0;
      final infer = (metrics['inferenceMs'] as num?)?.toDouble() ?? 0.0;
      final post = (metrics['decodeMs'] as num?)?.toDouble() ?? 0.0;
      final total = (metrics['totalLatencyMs'] as num?)?.toDouble() ??
          (metrics['totalMs'] as num?)?.toDouble() ??
          (prep + infer + post);

      _recentPrepTimes.add(prep);
      _recentInferTimes.add(infer);
      _recentPostTimes.add(post);
      _recentTotalTimes.add(total);

      if (_recentPrepTimes.length > 30) {
        _recentPrepTimes.removeAt(0);
        _recentInferTimes.removeAt(0);
        _recentPostTimes.removeAt(0);
        _recentTotalTimes.removeAt(0);
      }

      _lastBackend = (metrics['backend'] as String?) ?? _lastBackend;
      _lastHasDoc = (metrics['hasDocument'] as bool?) ?? false;
      _lastConf = (metrics['confidence'] as num?)?.toDouble() ?? 0.0;
    }

    _purgeOld(now);

    // Periodically log to developer console in debug mode
    if (kDebugMode && DateTime.now().difference(_lastLogTime).inMilliseconds >= 2500) {
      _lastLogTime = DateTime.now();
      debugPrint('[DocuRay Profiler] ${getMetrics()}');
    }
  }

  void _purgeOld(int now) {
    final cutoff = now - _windowDurationMs;
    while (_cameraFrameTimestamps.isNotEmpty && _cameraFrameTimestamps.first < cutoff) {
      _cameraFrameTimestamps.removeFirst();
    }
    while (_submittedFrameTimestamps.isNotEmpty && _submittedFrameTimestamps.first < cutoff) {
      _submittedFrameTimestamps.removeFirst();
    }
    while (_completedPredictionTimestamps.isNotEmpty && _completedPredictionTimestamps.first < cutoff) {
      _completedPredictionTimestamps.removeFirst();
    }
    while (_droppedFrameTimestamps.isNotEmpty && _droppedFrameTimestamps.first < cutoff) {
      _droppedFrameTimestamps.removeFirst();
    }
  }

  ScannerPerformanceMetrics getMetrics() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _purgeOld(now);

    final camFps = _cameraFrameTimestamps.length.toDouble();
    final subFps = _submittedFrameTimestamps.length.toDouble();
    final compFps = _completedPredictionTimestamps.length.toDouble();
    final dropFps = _droppedFrameTimestamps.length.toDouble();

    double avg(List<double> list) =>
        list.isEmpty ? 0.0 : list.reduce((a, b) => a + b) / list.length;

    return ScannerPerformanceMetrics(
      cameraFps: camFps,
      submittedFps: subFps,
      completedFps: compFps,
      droppedCount: _totalDroppedAllTime,
      droppedFps: dropFps,
      prepMs: avg(_recentPrepTimes),
      inferenceMs: avg(_recentInferTimes),
      postprocessMs: avg(_recentPostTimes),
      totalLatencyMs: avg(_recentTotalTimes),
      backend: _lastBackend,
      hasDocument: _lastHasDoc,
      confidence: _lastConf,
    );
  }

  void reset() {
    _cameraFrameTimestamps.clear();
    _submittedFrameTimestamps.clear();
    _completedPredictionTimestamps.clear();
    _droppedFrameTimestamps.clear();
    _recentPrepTimes.clear();
    _recentInferTimes.clear();
    _recentPostTimes.clear();
    _recentTotalTimes.clear();
  }
}

