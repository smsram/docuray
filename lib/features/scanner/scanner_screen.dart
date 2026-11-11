import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/providers/scanner_provider.dart';
import '../../core/providers/editor_provider.dart';
import '../../core/routing/app_router.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/services/native_scanner_service.dart';

/// Screen 3: Scanner UI with accurate live camera preview, best.tflite detection,
/// proper responsive layout fitting without overflow, and complete lifecycle management.
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _pulseController;
  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final scanner = context.read<ScannerProvider>();
      scanner.onAutoCaptured = (capturedPage) async {
        if (!mounted || _isNavigating) return;
        _isNavigating = true;

        // Immediately pause camera and release active camera resources
        await scanner.pauseCamera();

        if (!mounted) return;
        final editor = context.read<EditorProvider>();
        editor.addPage(capturedPage);

        await context.push(AppRouter.editor);
        _isNavigating = false;
        if (mounted) {
          await scanner.resumeCamera();
        }
      };

      scanner.initializeCamera();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final scanner = context.read<ScannerProvider>();
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      scanner.pauseCamera();
    } else if (state == AppLifecycleState.resumed && !_isNavigating) {
      scanner.resumeCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    try {
      context.read<ScannerProvider>().pauseCamera();
    } catch (_) {}
    super.dispose();
  }

  Future<void> _handleBack() async {
    final scanner = context.read<ScannerProvider>();
    final editor = context.read<EditorProvider>();

    if (editor.pages.isNotEmpty) {
      final shouldDiscard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Discard Scan?'),
          content: Text(
            'You have ${editor.pages.length} unsaved ${editor.pages.length == 1 ? "page" : "pages"}. Discarding will lose these pages.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.error,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );

      if (shouldDiscard == true && mounted) {
        await scanner.pauseCamera();
        editor.clearPages();
        if (mounted) {
          context.go(AppRouter.home);
        }
      }
    } else {
      await scanner.pauseCamera();
      if (mounted) {
        context.go(AppRouter.home);
      }
    }
  }

  void _onCapture() async {
    if (_isNavigating) return;
    final scanner = context.read<ScannerProvider>();
    final editor = context.read<EditorProvider>();
    if (scanner.isCapturing) return;

    final page = await scanner.captureDocument();
    if (page != null && mounted) {
      _isNavigating = true;
      // Immediately stop camera preview and release active camera resources
      await scanner.pauseCamera();
      editor.addPage(page);
      if (mounted) {
        await context.push(AppRouter.editor);
        _isNavigating = false;
        if (mounted) {
          await scanner.resumeCamera();
        }
      }
    }
  }

  bool _isImportingGallery = false;

  void _onImportGallery() async {
    if (_isNavigating || _isImportingGallery) return;
    _isImportingGallery = true;
    final scanner = context.read<ScannerProvider>();
    final editor = context.read<EditorProvider>();
    await scanner.pauseCamera();
    try {
      final pages = await scanner.importFromGallery();
      if (pages.isNotEmpty && mounted) {
        _isNavigating = true;
        for (final p in pages) {
          editor.addPage(p);
        }
        if (mounted) {
          await context.push(AppRouter.editor);
          _isNavigating = false;
          if (mounted) {
            await scanner.resumeCamera();
          }
        }
      } else if (mounted) {
        await scanner.resumeCamera();
      }
    } finally {
      _isImportingGallery = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scanner = context.watch<ScannerProvider>();
    final editor = context.watch<EditorProvider>();

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // 1. Top Toolbar (Compact, responsive, zero horizontal overflow)
            _buildTopToolbar(context, scanner),

            // 2. Center Viewfinder Area (Expanded, fits exact 3:4 camera aspect ratio without overflow)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const cameraAspectRatio = 3.0 / 4.0;
                    final maxW = constraints.maxWidth;
                    final maxH = constraints.maxHeight;

                    double viewW, viewH;
                    if (maxW / maxH > cameraAspectRatio) {
                      // Constrained by height
                      viewH = maxH;
                      viewW = maxH * cameraAspectRatio;
                    } else {
                      // Constrained by width
                      viewW = maxW;
                      viewH = maxW / cameraAspectRatio;
                    }

                    return Center(
                      child: SizedBox(
                        width: viewW,
                        height: viewH,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // Viewfinder container
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: _buildCameraViewfinder(scanner, viewW, viewH),
                            ),

                            // Floating Status Pill at top of viewfinder (long press toggles developer diagnostics)
                            Positioned(
                              top: 12,
                              left: 16,
                              right: 16,
                              child: Center(
                                child: GestureDetector(
                                  onLongPress: () {
                                    scanner.toggleDiagnostics();
                                  },
                                  child: _buildStatusPill(scanner),
                                ),
                              ),
                            ),

                            // Developer Performance Diagnostics HUD (hidden by default)
                            if (scanner.showDiagnostics && scanner.diagnosticMetrics != null)
                              Positioned(
                                bottom: 12,
                                left: 16,
                                right: 16,
                                child: _buildDiagnosticsHud(scanner.diagnosticMetrics!),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // 3. Bottom Controls Bar: Gallery, Shutter button, Review button
            _buildBottomControls(context, scanner, editor),
          ],
        ),
      ),
    );
  }

  Widget _buildTopToolbar(BuildContext context, ScannerProvider scanner) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Back button
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: _handleBack,
            tooltip: 'Back',
          ),

          // Two Independent Compact Dropdowns: Capture Type & Capture Mode
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Dropdown 1: Capture Type (Document / ID Card)
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(140),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withAlpha(50)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: scanner.captureType,
                        dropdownColor: const Color(0xFF1E232A),
                        icon: const Icon(Icons.arrow_drop_down, color: Colors.white, size: 18),
                        style: AppTypography.buttonSmall.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                        isDense: true,
                        items: const [
                          DropdownMenuItem(value: 'Document', child: Text('Document')),
                          DropdownMenuItem(value: 'ID Card', child: Text('ID Card')),
                        ],
                        onChanged: (v) {
                          if (v != null) scanner.setCaptureType(v);
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Dropdown 2: Capture Mode (Auto / Manual)
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(140),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: scanner.isAutoCapture
                            ? AppColors.primary.withAlpha(160)
                            : Colors.white.withAlpha(50),
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: scanner.captureMode,
                        dropdownColor: const Color(0xFF1E232A),
                        icon: const Icon(Icons.arrow_drop_down, color: Colors.white, size: 18),
                        style: AppTypography.buttonSmall.copyWith(
                          color: scanner.isAutoCapture ? AppColors.primary : Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                        isDense: true,
                        items: const [
                          DropdownMenuItem(value: 'Auto', child: Text('Auto')),
                          DropdownMenuItem(value: 'Manual', child: Text('Manual')),
                        ],
                        onChanged: (v) {
                          if (v != null) scanner.setCaptureMode(v);
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Flash Toggle
          IconButton(
            icon: _buildFlashIcon(scanner.flashMode),
            onPressed: scanner.cycleFlash,
            tooltip: 'Flash: ${scanner.flashMode.toUpperCase()}',
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPill(ScannerProvider scanner) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(
        color: _getStatusBgColor(scanner.state),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(80),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getStatusIcon(scanner.state),
            size: 15,
            color: Colors.white,
          ),
          const SizedBox(width: 6),
          Text(
            scanner.stateMessage,
            style: AppTypography.bodySmall.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls(BuildContext context, ScannerProvider scanner, EditorProvider editor) {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Single Gallery / Image Import Button
          IconButton(
            icon: const Icon(Icons.photo_library_outlined, size: 28, color: Colors.white),
            onPressed: _onImportGallery,
            tooltip: 'Import from Gallery',
          ),

          // Center Shutter Button with Loading State
          GestureDetector(
            onTap: scanner.isCapturing ? null : _onCapture,
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
              ),
              padding: const EdgeInsets.all(5),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scanner.state == ScannerState.ready
                      ? AppColors.success
                      : Colors.white,
                ),
                child: scanner.isCapturing
                    ? const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppColors.primary,
                          ),
                        ),
                      )
                    : null,
              ),
            ),
          ),

          // Review Session / Editor Button
          _buildReviewButton(editor),
        ],
      ),
    );
  }

  Widget _buildFlashIcon(String flashMode) {
    switch (flashMode) {
      case 'on':
        return const Icon(Icons.flash_on_rounded, color: AppColors.warning);
      case 'auto':
        return const Icon(Icons.flash_auto_rounded, color: Colors.white);
      default:
        return const Icon(Icons.flash_off_rounded, color: Colors.white70);
    }
  }

  Widget _buildReviewButton(EditorProvider editor) {
    final pageCount = editor.pages.length;
    final hasPages = pageCount > 0;

    return GestureDetector(
      onTap: hasPages
          ? () async {
              if (_isNavigating) return;
              _isNavigating = true;
              final scanner = context.read<ScannerProvider>();
              await scanner.pauseCamera();
              if (mounted) {
                await context.push(AppRouter.editor);
                _isNavigating = false;
                if (mounted) {
                  await scanner.resumeCamera();
                }
              }
            }
          : null,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: hasPages ? Colors.white24 : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasPages ? Colors.white70 : Colors.white24,
            width: 1.5,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              hasPages ? Icons.description_rounded : Icons.collections_bookmark_outlined,
              color: hasPages ? Colors.white : Colors.white38,
              size: 24,
            ),
            if (hasPages)
              Positioned(
                top: 2,
                right: 2,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$pageCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnosticsHud(Map<String, dynamic> m) {
    final fps = (m['fps'] as num?)?.toDouble() ?? 0.0;
    final totalMs = (m['totalMs'] as num?)?.toDouble() ?? 0.0;
    final inferMs = (m['inferenceMs'] as num?)?.toDouble() ?? 0.0;
    final decodeMs = (m['decodeMs'] as num?)?.toDouble() ?? 0.0;
    final maskMs = (m['maskMs'] as num?)?.toDouble() ?? 0.0;
    final contourMs = (m['contourMs'] as num?)?.toDouble() ?? 0.0;
    final postMs = decodeMs + maskMs + contourMs;
    final backend = m['backend'] as String? ?? 'CPU';
    final conf = ((m['confidence'] as num?)?.toDouble() ?? 0.0) * 100;
    final hasDoc = m['hasDocument'] as bool? ?? false;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(200),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'FPS: ${fps.toStringAsFixed(1)} | Total: ${totalMs.toStringAsFixed(1)}ms',
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 11,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                backend,
                style: const TextStyle(
                  color: Colors.cyanAccent,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Inf: ${inferMs.toStringAsFixed(1)}ms | Post: ${postMs.toStringAsFixed(1)}ms | Conf: ${conf.toStringAsFixed(0)}% | Quad: ${hasDoc ? "YES" : "NO"}',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraViewfinder(ScannerProvider scanner, double width, double height) {
    if (scanner.permissionDenied) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_rounded, size: 56, color: Colors.white70),
              const SizedBox(height: 12),
              Text(
                'Camera Access Required',
                style: AppTypography.screenTitle.copyWith(color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'DocuRay needs camera access to automatically detect paper corners and scan documents.',
                style: AppTypography.secondary.copyWith(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              PrimaryButton(
                label: 'Open Settings',
                onPressed: () => openAppSettings(),
              ),
              const SizedBox(height: 12),
              SecondaryButton(
                label: 'Import from Gallery',
                onPressed: _onImportGallery,
              ),
            ],
          ),
        ),
      );
    }

    if (scanner.isCameraReady) {
      if (NativeScannerService.isNativeSupported && ScannerProvider.useNativePlatformView) {
        return AndroidView(
          viewType: 'doc_scanner_view',
          onPlatformViewCreated: scanner.onNativeViewCreated,
        );
      }

      if (scanner.cameraController != null && scanner.cameraController!.value.isInitialized) {
        // Portrait aspect ratio of the raw camera stream (height / width)
        final camPortraitRatio = scanner.cameraController!.value.aspectRatio;
        final previewW = width;
        final previewH = width * camPortraitRatio;

        return Stack(
          fit: StackFit.expand,
          children: [
            // Live camera preview AND corner overlay inside the exact same FittedBox
            // so [0..1] camera coordinates map 1:1 to visible pixels without crop drift!
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: previewW,
                height: previewH,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CameraPreview(scanner.cameraController!),
                    _SmoothCornerOverlay(
                      targetCorners: scanner.detectedCorners,
                      isTracking: scanner.state == ScannerState.detected ||
                          scanner.state == ScannerState.holdSteady ||
                          scanner.state == ScannerState.ready ||
                          scanner.state == ScannerState.capturing,
                      isReady: scanner.state == ScannerState.ready,
                      pulseValue: _pulseController.value,
                      captureType: scanner.captureType,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      }
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: AppColors.primary),
          const SizedBox(height: 16),
          Text(
            'Starting camera...',
            style: AppTypography.secondary.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Color _getStatusBgColor(ScannerState state) {
    switch (state) {
      case ScannerState.ready:
        return AppColors.success.withAlpha(220);
      case ScannerState.failed:
      case ScannerState.qualityProblem:
        return AppColors.error.withAlpha(220);
      case ScannerState.holdSteady:
        return AppColors.warning.withAlpha(220);
      case ScannerState.detected:
        return AppColors.primary.withAlpha(220);
      case ScannerState.searching:
      case ScannerState.capturing:
      case ScannerState.processing:
        return Colors.black.withAlpha(180);
    }
  }

  IconData _getStatusIcon(ScannerState state) {
    switch (state) {
      case ScannerState.ready:
        return Icons.check_circle_rounded;
      case ScannerState.failed:
        return Icons.error_outline_rounded;
      case ScannerState.qualityProblem:
        return Icons.warning_amber_rounded;
      case ScannerState.holdSteady:
        return Icons.pan_tool_rounded;
      case ScannerState.detected:
        return Icons.crop_free_rounded;
      case ScannerState.searching:
      case ScannerState.capturing:
      case ScannerState.processing:
        return Icons.search_rounded;
    }
  }
}

/// Smooth, independent corner-dot tracking overlay with physics-based interpolation
/// and graceful loss-of-detection handling.
class _SmoothCornerOverlay extends StatefulWidget {
  final List<Offset> targetCorners;
  final bool isTracking;
  final bool isReady;
  final double pulseValue;
  final String captureType;

  const _SmoothCornerOverlay({
    required this.targetCorners,
    required this.isTracking,
    required this.isReady,
    required this.pulseValue,
    required this.captureType,
  });

  @override
  State<_SmoothCornerOverlay> createState() => _SmoothCornerOverlayState();
}

class _SmoothCornerOverlayState extends State<_SmoothCornerOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _tickerController;
  DateTime _lastFrameTime = DateTime.now();

  List<Offset> _currentCorners = [];
  List<Offset> _targetCorners = [];
  DateTime _lastValidDetectionTime = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _initCorners(widget.targetCorners);

    // Continuous vsync ticker for 60fps/120fps fluid independent corner movement
    _tickerController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_onTick);
    _tickerController.repeat();
  }

  void _initCorners(List<Offset> corners) {
    if (corners.length >= 4) {
      _currentCorners = List.from(corners);
      _targetCorners = List.from(corners);
      _lastValidDetectionTime = DateTime.now();
    } else {
      _currentCorners = const [
        Offset(0.08, 0.08),
        Offset(0.92, 0.08),
        Offset(0.92, 0.92),
        Offset(0.08, 0.92),
      ];
      _targetCorners = List.from(_currentCorners);
    }
  }

  @override
  void didUpdateWidget(covariant _SmoothCornerOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.targetCorners.length >= 4) {
      _targetCorners = List.from(widget.targetCorners);
      if (widget.isTracking) {
        _lastValidDetectionTime = DateTime.now();
      }
    }
  }

  @override
  void dispose() {
    _tickerController.dispose();
    super.dispose();
  }

  void _onTick() {
    final now = DateTime.now();
    final dt = now.difference(_lastFrameTime).inMicroseconds / 1000000.0;
    _lastFrameTime = now;

    if (dt <= 0.0 || dt > 0.1) return;

    // Independent smooth exponential pursuit towards target (rate: ~22.0/s)
    // Smooths out high-frequency sensor noise while responding instantly to camera movement
    final factor = (1.0 - math.exp(-22.0 * dt)).clamp(0.05, 1.0);

    bool moved = false;
    for (int i = 0; i < 4 && i < _currentCorners.length && i < _targetCorners.length; i++) {
      final cur = _currentCorners[i];
      final tgt = _targetCorners[i];
      final dx = tgt.dx - cur.dx;
      final dy = tgt.dy - cur.dy;

      if (dx.abs() > 0.0001 || dy.abs() > 0.0001) {
        _currentCorners[i] = Offset(
          cur.dx + dx * factor,
          cur.dy + dy * factor,
        );
        moved = true;
      }
    }

    if (moved && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    // Graceful momentary loss handling: retain visible corners for up to 350ms before fading out
    final timeSinceDetection = DateTime.now().difference(_lastValidDetectionTime).inMilliseconds;
    final bool shouldShow = widget.isTracking || timeSinceDetection < 350;

    return AnimatedOpacity(
      opacity: shouldShow ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      child: CustomPaint(
        painter: _CornerDetectionPainter(
          corners: _currentCorners,
          isReady: widget.isReady,
          pulseValue: widget.pulseValue,
          captureType: widget.captureType,
          isTracking: shouldShow,
        ),
      ),
    );
  }
}

/// Draws ONLY FOUR SMOOTH CIRCULAR CORNER INDICATORS (NO polygon or frame lines) + ID Card Guide
class _CornerDetectionPainter extends CustomPainter {
  final List<Offset> corners;
  final bool isReady;
  final double pulseValue;
  final String captureType;
  final bool isTracking;

  _CornerDetectionPainter({
    required this.corners,
    required this.isReady,
    required this.pulseValue,
    required this.captureType,
    required this.isTracking,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw ID Card Guide if in ID Card mode
    if (captureType.toLowerCase() == 'id card') {
      final cardW = size.width * 0.88;
      final cardH = cardW / 1.5858;
      final left = (size.width - cardW) / 2;
      final top = (size.height - cardH) / 2;
      final cardRect = Rect.fromLTWH(left, top, cardW, cardH);
      final rrect = RRect.fromRectAndRadius(cardRect, const Radius.circular(16));

      final guidePaint = Paint()
        ..color = Colors.white.withAlpha(100)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawRRect(rrect, guidePaint);

      // Corner brackets
      final bracketPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5;
      const bracketLen = 24.0;
      // Top-Left
      canvas.drawLine(Offset(left, top + bracketLen), Offset(left, top + 16), bracketPaint);
      canvas.drawLine(Offset(left + 16, top), Offset(left + bracketLen, top), bracketPaint);
      // Top-Right
      canvas.drawLine(Offset(left + cardW, top + bracketLen), Offset(left + cardW, top + 16), bracketPaint);
      canvas.drawLine(Offset(left + cardW - 16, top), Offset(left + cardW - bracketLen, top), bracketPaint);
      // Bottom-Right
      canvas.drawLine(Offset(left + cardW, top + cardH - bracketLen), Offset(left + cardW, top + cardH - 16), bracketPaint);
      canvas.drawLine(Offset(left + cardW - 16, top + cardH), Offset(left + cardW - bracketLen, top + cardH), bracketPaint);
      // Bottom-Left
      canvas.drawLine(Offset(left, top + cardH - bracketLen), Offset(left, top + cardH - 16), bracketPaint);
      canvas.drawLine(Offset(left + 16, top + cardH), Offset(left + bracketLen, top + cardH), bracketPaint);
    }

    if (!isTracking || corners.length < 4) return;

    final actualPoints = corners.map((c) => Offset(c.dx * size.width, c.dy * size.height)).toList();
    final activeColor = isReady ? AppColors.success : AppColors.primary;

    // 2. Render ONLY the FOUR SMOOTH CIRCULAR CORNER INDICATORS
    // No polygon lines, no frame outlines, no bounding boxes
    for (final pt in actualPoints) {
      // (a) Deep contrast shadow backing so the dot is legible on pure white paper or any background
      canvas.drawCircle(
        pt,
        11.0,
        Paint()
          ..color = Colors.black.withAlpha(140)
          ..style = PaintingStyle.fill,
      );

      // (b) Outer animated pulsing reticle / halo ring
      final haloRadius = isReady ? (16.0 + pulseValue * 6.0) : (13.5 + pulseValue * 4.0);
      final haloAlpha = isReady ? (120 + (pulseValue * 70).toInt()) : (70 + (pulseValue * 40).toInt());
      canvas.drawCircle(
        pt,
        haloRadius,
        Paint()
          ..color = activeColor.withAlpha(haloAlpha.clamp(0, 255))
          ..style = PaintingStyle.stroke
          ..strokeWidth = isReady ? 2.5 : 2.0,
      );

      // (c) When ready: an additional vibrant outer aura ring for unmistakable capture confirmation
      if (isReady) {
        canvas.drawCircle(
          pt,
          23.0 + (pulseValue * 4.0),
          Paint()
            ..color = AppColors.success.withAlpha((40 + (pulseValue * 30).toInt()).clamp(0, 255))
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }

      // (d) Main solid circular indicator disc
      canvas.drawCircle(
        pt,
        8.5,
        Paint()
          ..color = activeColor
          ..style = PaintingStyle.fill,
      );

      // (e) Subtle dark ring separating the disc and the center reticle core
      canvas.drawCircle(
        pt,
        4.5,
        Paint()
          ..color = Colors.black.withAlpha(70)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );

      // (f) Center white precision reticle dot
      canvas.drawCircle(
        pt,
        3.5,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CornerDetectionPainter oldDelegate) => true;
}
