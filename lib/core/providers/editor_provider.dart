import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import '../../models/models.dart';
import '../services/perspective_transform.dart';
import '../services/image_enhancer.dart';
import '../services/native_scanner_service.dart';
import '../services/pdf_generator_service.dart';
import '../services/local_document_repository.dart';

// ---------------------------------------------------------------------------
// Flutter slider -> native DocumentProcessingEngine scale helpers.
//   brightness: Flutter -0.5..0.5  ->  native -50..50
//   contrast:   Flutter -0.5..0.5  ->  native -50..50
// ---------------------------------------------------------------------------
double _toNativeBrightness(double v) => v * 100.0;
double _toNativeContrast(double v)   => v * 100.0;

enum EditorActiveTool {
  none,
  crop,
  filter,
  adjust,
}

/// Provider managing scan editor state: pages, interactive corners, filters,
/// adjustments, real-time preview rendering, and full-resolution PDF/image saving.
class EditorProvider extends ChangeNotifier {
  List<DocumentPage> _pages = [];
  int _currentPageIndex = 0;
  EditorActiveTool _activeTool = EditorActiveTool.none;
  String _documentTitle = '';

  // Active draggable corner positions (normalized 0.0 - 1.0)
  List<Offset> _cornerPoints = [
    const Offset(0.05, 0.05),
    const Offset(0.95, 0.05),
    const Offset(0.95, 0.95),
    const Offset(0.05, 0.95),
  ];

  // Active rendered preview image bytes & original comparison cache
  Uint8List? _activePreviewBytes;
  Uint8List? _originalPreviewBytes;
  bool _isComparing = false;
  bool _isProcessingPreview = false;
  bool _isSaving = false;
  int? _lastExportSizeBytes;

  Timer? _adjustmentDebounce;

  List<DocumentPage> get pages => _pages;
  int get currentPageIndex => _currentPageIndex;
  EditorActiveTool get activeTool => _activeTool;
  String get documentTitle => _documentTitle;
  List<Offset> get cornerPoints => _cornerPoints;
  Uint8List? get activePreviewBytes => _activePreviewBytes;
  Uint8List? get originalPreviewBytes => _originalPreviewBytes;
  bool get isComparing => _isComparing;
  bool get isProcessingPreview => _isProcessingPreview;
  bool get isSaving => _isSaving;
  int? get lastExportSizeBytes => _lastExportSizeBytes;
  String get lastExportSizeFormatted => _lastExportSizeBytes != null
      ? PdfGeneratorService.formatFileSize(_lastExportSizeBytes!)
      : '';

  /// Currently visible preview bytes based on whether user is holding Compare button
  Uint8List? get displayedPreviewBytes =>
      _isComparing ? (_originalPreviewBytes ?? _activePreviewBytes) : _activePreviewBytes;

  void setIsComparing(bool val) {
    if (_isComparing != val) {
      _isComparing = val;
      notifyListeners();
    }
  }

  void setDocumentTitle(String title) {
    _documentTitle = title;
    notifyListeners();
  }

  DocumentPage? get currentPage {
    if (_pages.isEmpty || _currentPageIndex < 0 || _currentPageIndex >= _pages.length) {
      return null;
    }
    return _pages[_currentPageIndex];
  }

  void initializeWithPages(List<DocumentPage> initialPages, {String? title}) {
    if (initialPages.isNotEmpty) {
      _pages = List.from(initialPages);
    } else {
      _pages = [
        const DocumentPage(id: 'page_1', pageNumber: 1, filterType: 'auto'),
      ];
    }
    _currentPageIndex = 0;
    if (initialPages.isNotEmpty && initialPages.first.autoDetectedCorners == null) {
      _activeTool = EditorActiveTool.crop;
    } else {
      _activeTool = EditorActiveTool.none;
    }
    if (title != null && title.isNotEmpty) {
      _documentTitle = title;
    } else if (_documentTitle.isEmpty) {
      final now = DateTime.now();
      _documentTitle =
          'Scan ${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    }
    _syncCornerPoints();
    _triggerPreviewUpdate();
    notifyListeners();
  }

  void clearPages() {
    _pages.clear();
    _currentPageIndex = 0;
    _activeTool = EditorActiveTool.none;
    _cornerPoints = [
      const Offset(0.05, 0.05),
      const Offset(0.95, 0.05),
      const Offset(0.95, 0.95),
      const Offset(0.05, 0.95),
    ];
    _activePreviewBytes = null;
    _originalPreviewBytes = null;
    _isComparing = false;
    _documentTitle = '';
    _lastExportSizeBytes = null;
    notifyListeners();
  }

  void _syncCornerPoints() {
    final page = currentPage;
    if (page != null && page.corners.length == 4) {
      _cornerPoints = page.corners.map((c) => Offset(c.x, c.y)).toList();
    } else {
      _cornerPoints = [
        const Offset(0.05, 0.05),
        const Offset(0.95, 0.05),
        const Offset(0.95, 0.95),
        const Offset(0.05, 0.95),
      ];
    }
  }

  void setPageIndex(int index) {
    if (index >= 0 && index < _pages.length) {
      _currentPageIndex = index;
      _syncCornerPoints();
      _triggerPreviewUpdate();
      notifyListeners();
    }
  }

  void setActiveTool(EditorActiveTool tool) {
    final previous = _activeTool;
    _activeTool = _activeTool == tool ? EditorActiveTool.none : tool;

    // If closing crop tool, refresh preview with new corners
    if (previous == EditorActiveTool.crop && _activeTool != EditorActiveTool.crop) {
      _triggerPreviewUpdate();
    }

    notifyListeners();
  }

  void updateCornerPoint(int index, Offset newNormalizedOffset) {
    if (index >= 0 && index < _cornerPoints.length) {
      final clamped = Offset(
        newNormalizedOffset.dx.clamp(0.0, 1.0),
        newNormalizedOffset.dy.clamp(0.0, 1.0),
      );
      _cornerPoints[index] = clamped;

      if (currentPage != null) {
        final updatedCorners = _cornerPoints.map((p) => CornerPoint(p.dx, p.dy)).toList();
        _pages[_currentPageIndex] = currentPage!.copyWith(corners: updatedCorners);
      }
      notifyListeners();
    }
  }

  /// Draggable edge handle updater.
  /// edgeIndex: 0 = Top, 1 = Right, 2 = Bottom, 3 = Left
  void updateEdge(int edgeIndex, Offset deltaNormalized) {
    if (_cornerPoints.length < 4) return;

    switch (edgeIndex) {
      case 0: // Top edge -> affects TL (0) and TR (1)
        final newTL = Offset(
          (_cornerPoints[0].dx + deltaNormalized.dx).clamp(0.0, 1.0),
          (_cornerPoints[0].dy + deltaNormalized.dy).clamp(0.0, _cornerPoints[3].dy - 0.05),
        );
        final newTR = Offset(
          (_cornerPoints[1].dx + deltaNormalized.dx).clamp(0.0, 1.0),
          (_cornerPoints[1].dy + deltaNormalized.dy).clamp(0.0, _cornerPoints[2].dy - 0.05),
        );
        _cornerPoints[0] = newTL;
        _cornerPoints[1] = newTR;
        break;
      case 1: // Right edge -> affects TR (1) and BR (2)
        final newTR = Offset(
          (_cornerPoints[1].dx + deltaNormalized.dx).clamp(_cornerPoints[0].dx + 0.05, 1.0),
          (_cornerPoints[1].dy + deltaNormalized.dy).clamp(0.0, 1.0),
        );
        final newBR = Offset(
          (_cornerPoints[2].dx + deltaNormalized.dx).clamp(_cornerPoints[3].dx + 0.05, 1.0),
          (_cornerPoints[2].dy + deltaNormalized.dy).clamp(0.0, 1.0),
        );
        _cornerPoints[1] = newTR;
        _cornerPoints[2] = newBR;
        break;
      case 2: // Bottom edge -> affects BR (2) and BL (3)
        final newBR = Offset(
          (_cornerPoints[2].dx + deltaNormalized.dx).clamp(0.0, 1.0),
          (_cornerPoints[2].dy + deltaNormalized.dy).clamp(_cornerPoints[1].dy + 0.05, 1.0),
        );
        final newBL = Offset(
          (_cornerPoints[3].dx + deltaNormalized.dx).clamp(0.0, 1.0),
          (_cornerPoints[3].dy + deltaNormalized.dy).clamp(_cornerPoints[0].dy + 0.05, 1.0),
        );
        _cornerPoints[2] = newBR;
        _cornerPoints[3] = newBL;
        break;
      case 3: // Left edge -> affects BL (3) and TL (0)
        final newBL = Offset(
          (_cornerPoints[3].dx + deltaNormalized.dx).clamp(0.0, _cornerPoints[2].dx - 0.05),
          (_cornerPoints[3].dy + deltaNormalized.dy).clamp(0.0, 1.0),
        );
        final newTL = Offset(
          (_cornerPoints[0].dx + deltaNormalized.dx).clamp(0.0, _cornerPoints[1].dx - 0.05),
          (_cornerPoints[0].dy + deltaNormalized.dy).clamp(0.0, 1.0),
        );
        _cornerPoints[3] = newBL;
        _cornerPoints[0] = newTL;
        break;
    }

    if (currentPage != null) {
      final updatedCorners = _cornerPoints.map((p) => CornerPoint(p.dx, p.dy)).toList();
      _pages[_currentPageIndex] = currentPage!.copyWith(corners: updatedCorners);
    }
    notifyListeners();
  }

  /// Restores automatically detected corners if available, or full image framing.
  void resetCrop() {
    final page = currentPage;
    if (page != null && page.autoDetectedCorners != null && page.autoDetectedCorners!.length == 4) {
      _cornerPoints = page.autoDetectedCorners!.map((c) => Offset(c.x, c.y)).toList();
    } else {
      _cornerPoints = const [
        Offset(0.0, 0.0),
        Offset(1.0, 0.0),
        Offset(1.0, 1.0),
        Offset(0.0, 1.0),
      ];
    }
    if (currentPage != null) {
      final updatedCorners = _cornerPoints.map((p) => CornerPoint(p.dx, p.dy)).toList();
      _pages[_currentPageIndex] = currentPage!.copyWith(corners: updatedCorners);
    }
    _triggerPreviewUpdate();
    notifyListeners();
  }

  /// Restores entire full-frame image boundary
  void resetToFullFrame() {
    _cornerPoints = const [
      Offset(0.0, 0.0),
      Offset(1.0, 0.0),
      Offset(1.0, 1.0),
      Offset(0.0, 1.0),
    ];
    if (currentPage != null) {
      final updatedCorners = _cornerPoints.map((p) => CornerPoint(p.dx, p.dy)).toList();
      _pages[_currentPageIndex] = currentPage!.copyWith(corners: updatedCorners);
    }
    _triggerPreviewUpdate();
    notifyListeners();
  }

  /// Straightens current corners into an axis-aligned rectangle
  void straightenCrop() {
    if (_cornerPoints.length == 4) {
      final minX = math.min(_cornerPoints[0].dx, _cornerPoints[3].dx);
      final maxX = math.max(_cornerPoints[1].dx, _cornerPoints[2].dx);
      final minY = math.min(_cornerPoints[0].dy, _cornerPoints[1].dy);
      final maxY = math.max(_cornerPoints[3].dy, _cornerPoints[2].dy);

      _cornerPoints = [
        Offset(minX.clamp(0.0, 1.0), minY.clamp(0.0, 1.0)),
        Offset(maxX.clamp(0.0, 1.0), minY.clamp(0.0, 1.0)),
        Offset(maxX.clamp(0.0, 1.0), maxY.clamp(0.0, 1.0)),
        Offset(minX.clamp(0.0, 1.0), maxY.clamp(0.0, 1.0)),
      ];

      if (currentPage != null) {
        final updatedCorners = _cornerPoints.map((p) => CornerPoint(p.dx, p.dy)).toList();
        _pages[_currentPageIndex] = currentPage!.copyWith(corners: updatedCorners);
      }
      _triggerPreviewUpdate();
      notifyListeners();
    }
  }

  void setFilter(String filterType) {
    if (currentPage != null) {
      _pages[_currentPageIndex] = currentPage!.copyWith(filterType: filterType);
      _triggerPreviewUpdate();
      notifyListeners();
    }
  }

  void setAdjustments({double? brightness, double? contrast, double? sharpness}) {
    if (currentPage != null) {
      _pages[_currentPageIndex] = currentPage!.copyWith(
        brightness: brightness ?? currentPage!.brightness,
        contrast: contrast ?? currentPage!.contrast,
        sharpness: sharpness ?? currentPage!.sharpness,
      );
      // Debounce slider adjustments to keep interaction 60fps smooth
      _adjustmentDebounce?.cancel();
      _adjustmentDebounce = Timer(const Duration(milliseconds: 90), () {
        _triggerPreviewUpdate();
      });
      notifyListeners();
    }
  }

  void rotateCurrentPage() {
    if (currentPage != null) {
      final currentRotation = currentPage!.rotationDegrees;
      _pages[_currentPageIndex] = currentPage!.copyWith(
        rotationDegrees: (currentRotation + 90) % 360,
      );
      _triggerPreviewUpdate();
      notifyListeners();
    }
  }

  void rotatePageAt(int index) {
    if (index >= 0 && index < _pages.length) {
      final p = _pages[index];
      _pages[index] = p.copyWith(rotationDegrees: (p.rotationDegrees + 90) % 360);
      if (index == _currentPageIndex) {
        _triggerPreviewUpdate();
      }
      notifyListeners();
    }
  }

  void addPage(DocumentPage page) {
    if (_documentTitle.isEmpty) {
      final now = DateTime.now();
      _documentTitle =
          'Scan ${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    }
    final newPageNumber = _pages.length + 1;
    _pages.add(page.copyWith(pageNumber: newPageNumber));
    _currentPageIndex = _pages.length - 1;
    if (_pages.length == 1 && page.autoDetectedCorners == null) {
      _activeTool = EditorActiveTool.crop;
    }
    _syncCornerPoints();
    _triggerPreviewUpdate();
    notifyListeners();
  }

  void deletePageAt(int index) {
    if (_pages.length <= 1) return;
    _pages.removeAt(index);
    for (int i = 0; i < _pages.length; i++) {
      _pages[i] = _pages[i].copyWith(pageNumber: i + 1);
    }
    if (_currentPageIndex >= _pages.length) {
      _currentPageIndex = _pages.length - 1;
    }
    _syncCornerPoints();
    _triggerPreviewUpdate();
    notifyListeners();
  }

  void reorderPages(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = _pages.removeAt(oldIndex);
    _pages.insert(newIndex, item);
    for (int i = 0; i < _pages.length; i++) {
      _pages[i] = _pages[i].copyWith(pageNumber: i + 1);
    }
    _currentPageIndex = newIndex;
    _syncCornerPoints();
    _triggerPreviewUpdate();
    notifyListeners();
  }

  /// Triggers asynchronous preview generation for the current page.
  /// On Android: single-pass native pipeline for blazing fast responsiveness.
  /// Fallback: runs the matching pure Dart pipeline.
  void _triggerPreviewUpdate() async {
    final page = currentPage;
    if (page == null || page.originalImagePath == null) {
      _activePreviewBytes = null;
      _originalPreviewBytes = null;
      notifyListeners();
      return;
    }

    final file = File(page.originalImagePath!);
    if (!await file.exists()) {
      _activePreviewBytes = null;
      _originalPreviewBytes = null;
      notifyListeners();
      return;
    }

    _isProcessingPreview = true;
    notifyListeners();

    try {
      final corners = page.corners.isNotEmpty
          ? page.corners
          : _cornerPoints.map((p) => CornerPoint(p.dx, p.dy)).toList();
      final isFullPage = corners.length == 4 &&
          corners[0].x <= 0.01 && corners[0].y <= 0.01 &&
          corners[2].x >= 0.99 && corners[2].y >= 0.99;
      final points = isFullPage
          ? null
          : [
              corners[0].x, corners[0].y,
              corners[1].x, corners[1].y,
              corners[2].x, corners[2].y,
              corners[3].x, corners[3].y,
            ];

      // ---- Native path (Android) ----------------------------------------
      if (NativeScannerService.isNativeSupported) {
        // 1. Process active preview with current filter and adjustments
        final previewOut = await NativeScannerService.processPage(
          page.originalImagePath!,
          points: points,
          degrees: page.rotationDegrees,
          filter: page.filterType,
          brightness: _toNativeBrightness(page.brightness),
          contrast: _toNativeContrast(page.contrast),
          sharpness: page.sharpness,
          maxDimension: 960,
          quality: 82,
        );

        if (previewOut != null && await File(previewOut).exists()) {
          _activePreviewBytes = await File(previewOut).readAsBytes();
        }

        // 2. Cache un-filtered, un-adjusted preview for instantaneous Compare
        final originalOut = await NativeScannerService.processPage(
          page.originalImagePath!,
          points: points,
          degrees: page.rotationDegrees,
          filter: 'original',
          brightness: 0.0,
          contrast: 0.0,
          sharpness: 0.0,
          maxDimension: 960,
          quality: 82,
        );

        if (originalOut != null && await File(originalOut).exists()) {
          _originalPreviewBytes = await File(originalOut).readAsBytes();
        }
        return;
      }

      // ---- Dart fallback ------------------------------------------------
      final bytes = await file.readAsBytes();
      var rawImg = img.decodeImage(bytes);
      if (rawImg != null) {
        rawImg = img.bakeOrientation(rawImg);
        // Downscale to 960px max dimension for fast editing preview
        if (rawImg.width > 960 || rawImg.height > 960) {
          rawImg = img.copyResize(
            rawImg,
            width: rawImg.width > rawImg.height ? 960 : null,
            height: rawImg.height >= rawImg.width ? 960 : null,
          );
        }

        var warped = PerspectiveTransform.warp(source: rawImg, corners: corners);
        if (page.rotationDegrees != 0) {
          warped = img.copyRotate(warped, angle: page.rotationDegrees);
        }

        _originalPreviewBytes = Uint8List.fromList(img.encodeJpg(warped, quality: 82));

        final enhanced = ImageEnhancer.process(
          source: warped,
          filterType: page.filterType,
          brightness: page.brightness,
          contrast: page.contrast,
          sharpness: page.sharpness,
        );

        _activePreviewBytes = Uint8List.fromList(img.encodeJpg(enhanced, quality: 82));
      }
    } catch (e) {
      debugPrint('[DocuRay] Preview generation error: $e');
    } finally {
      _isProcessingPreview = false;
      notifyListeners();
    }
  }

  /// Performs full-resolution non-destructive rendering of all pages,
  /// generates multi-page PDF with the selected export quality, and persists Document to disk.
  Future<Document> saveDocument({
    String? title,
    PdfExportQuality exportQuality = PdfExportQuality.standard,
  }) async {
    _isSaving = true;
    notifyListeners();

    try {
      final effectiveTitle = (title != null && title.trim().isNotEmpty)
          ? title.trim()
          : (_documentTitle.trim().isNotEmpty
              ? _documentTitle.trim()
              : 'Scan ${DateTime.now().millisecondsSinceEpoch}');

      final docId = 'doc_${DateTime.now().millisecondsSinceEpoch}';
      final appDir = await getApplicationDocumentsDirectory();
      final docDir = Directory('${appDir.path}/documents/$docId');
      if (!await docDir.exists()) {
        await docDir.create(recursive: true);
      }

      final processedPages = <DocumentPage>[];
      final useNative = NativeScannerService.isNativeSupported;

      for (int i = 0; i < _pages.length; i++) {
        final p = _pages[i];
        final pageNum = i + 1;

        if (p.originalImagePath != null && await File(p.originalImagePath!).exists()) {
          // Copy raw captured original into permanent storage - NEVER overwritten
          final origExt = p.originalImagePath!.split('.').last.toLowerCase();
          final ext = (origExt == 'jpg' || origExt == 'jpeg' || origExt == 'png') ? origExt : 'jpg';
          final permOrigPath = '${docDir.path}/page_${pageNum}_original.$ext';
          await File(p.originalImagePath!).copy(permOrigPath);

          final processedPath = '${docDir.path}/page_${pageNum}_processed.jpg';

          final corners = p.corners.isNotEmpty
              ? p.corners
              : const [
                  CornerPoint(0.0, 0.0),
                  CornerPoint(1.0, 0.0),
                  CornerPoint(1.0, 1.0),
                  CornerPoint(0.0, 1.0),
                ];
          final isFullPage = corners.length == 4 &&
              corners[0].x <= 0.01 && corners[0].y <= 0.01 &&
              corners[2].x >= 0.99 && corners[2].y >= 0.99;
          final points = isFullPage
              ? null
              : [
                  corners[0].x, corners[0].y,
                  corners[1].x, corners[1].y,
                  corners[2].x, corners[2].y,
                  corners[3].x, corners[3].y,
                ];

          if (useNative) {
            // Full-resolution native processing at the selected export quality
            final outPath = await NativeScannerService.processPage(
              permOrigPath,
              points: points,
              degrees: p.rotationDegrees,
              filter: p.filterType,
              brightness: _toNativeBrightness(p.brightness),
              contrast: _toNativeContrast(p.contrast),
              sharpness: p.sharpness,
              maxDimension: exportQuality.maxDimension,
              quality: exportQuality.jpegQuality,
            );

            if (outPath != null && await File(outPath).exists()) {
              await File(outPath).copy(processedPath);
            } else {
              await File(permOrigPath).copy(processedPath);
            }
          } else {
            // Full-resolution Dart processing fallback
            final rawBytes = await File(permOrigPath).readAsBytes();
            var fullImg = img.decodeImage(rawBytes);

            if (fullImg != null) {
              fullImg = img.bakeOrientation(fullImg);
              var processed = PerspectiveTransform.warp(source: fullImg, corners: corners);
              if (p.rotationDegrees != 0) {
                processed = img.copyRotate(processed, angle: p.rotationDegrees);
              }
              processed = ImageEnhancer.process(
                source: processed,
                filterType: p.filterType,
                brightness: p.brightness,
                contrast: p.contrast,
                sharpness: p.sharpness,
              );

              // Downscale if image exceeds preset max dimension (never upscale)
              if (processed.width > exportQuality.maxDimension || processed.height > exportQuality.maxDimension) {
                final isWLonger = processed.width >= processed.height;
                processed = img.copyResize(
                  processed,
                  width: isWLonger ? exportQuality.maxDimension : null,
                  height: !isWLonger ? exportQuality.maxDimension : null,
                );
              }

              await File(processedPath).writeAsBytes(
                img.encodeJpg(processed, quality: exportQuality.jpegQuality),
              );
            } else {
              await File(permOrigPath).copy(processedPath);
            }
          }

          // Generate thumbnail from processed image
          final thumbPath = '${docDir.path}/page_${pageNum}_thumb.jpg';
          try {
            final procBytes = await File(processedPath).readAsBytes();
            final procImg = img.decodeImage(procBytes);
            if (procImg != null) {
              final thumbImg = img.copyResize(procImg, width: 240);
              await File(thumbPath).writeAsBytes(img.encodeJpg(thumbImg, quality: 75));
            }
          } catch (_) {}

          processedPages.add(
            p.copyWith(
              pageNumber: pageNum,
              originalImagePath: permOrigPath,
              processedImagePath: processedPath,
              thumbnailPath: await File(thumbPath).exists() ? thumbPath : null,
            ),
          );
        } else {
          processedPages.add(p.copyWith(pageNumber: pageNum));
        }
      }

      // Generate multi-page PDF
      final safeFileName = effectiveTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final pdfPath = '${docDir.path}/$safeFileName.pdf';
      final pdfFile = await PdfGeneratorService.generatePdf(
        pages: processedPages,
        outputPath: pdfPath,
        documentTitle: effectiveTitle,
        quality: exportQuality,
      );

      _lastExportSizeBytes = await pdfFile.length();

      final primaryThumbPath = processedPages.isNotEmpty ? processedPages.first.thumbnailPath : null;

      final document = Document(
        id: docId,
        title: effectiveTitle,
        pages: processedPages,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        pdfPath: pdfPath,
        thumbnailPath: primaryThumbPath,
        format: DocumentFormat.pdf,
        syncMetadata: const SyncMetadata(status: SyncStatus.notSynced),
      );

      await LocalDocumentRepository.instance.saveDocument(document);

      return document;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _adjustmentDebounce?.cancel();
    super.dispose();
  }
}
