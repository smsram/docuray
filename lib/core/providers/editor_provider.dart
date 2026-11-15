import 'dart:async';
import 'dart:convert';
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
import 'settings_provider.dart';

// ---------------------------------------------------------------------------
// Flutter slider -> native DocumentProcessingEngine scale helpers.
//   brightness: Flutter -0.5..0.5  ->  native -50..50
//   contrast:   Flutter -0.5..0.5  ->  native -50..50
// ---------------------------------------------------------------------------
double _toNativeBrightness(double v) => v * 100.0;
double _toNativeContrast(double v)   => v * 100.0;

/// All 16 functional editing options in the exact required toolbar order
enum EditorActiveTool {
  none,
  crop,       // 1
  rotate,     // 2
  filter,     // 3
  adjust,     // 4
  retake,     // 5
  erase,      // 6
  annotate,   // 7
  watermark,  // 8
  redact,     // 9
  resize,     // 10
  margins,    // 11
  border,     // 12
  reorder,    // 13
  undo,       // 14
  redo,       // 15
  reset,      // 16
}

/// Snapshot of editor state for Undo / Redo operations.
class EditorHistorySnapshot {
  final List<DocumentPage> pages;
  final int currentPageIndex;
  final String description;

  const EditorHistorySnapshot({
    required this.pages,
    required this.currentPageIndex,
    required this.description,
  });
}

/// Provider managing scan editor state: pages, interactive corners, filters,
/// adjustments, real-time preview rendering, and full-resolution PDF/image saving.
class EditorProvider extends ChangeNotifier {
  List<DocumentPage> _pages = [];
  int _currentPageIndex = 0;
  EditorActiveTool _activeTool = EditorActiveTool.none;
  String _documentTitle = '';

  // Document identity tracking for editing existing PDFs
  String? _documentId;
  String? _existingPdfPath;
  bool _isEditingExisting = false;

  // Retake page state
  int? _retakePageIndex;
  int? get retakePageIndex => _retakePageIndex;
  bool get isRetaking => _retakePageIndex != null;

  void startRetake(int pageIndex) {
    _retakePageIndex = pageIndex;
    notifyListeners();
  }

  void cancelRetake() {
    _retakePageIndex = null;
    notifyListeners();
  }

  // Undo / Redo history stacks
  final List<EditorHistorySnapshot> _undoStack = [];
  final List<EditorHistorySnapshot> _redoStack = [];
  static const int _maxHistoryDepth = 30;

  // Request ID tracking to discard stale asynchronous preview updates during rapid switching
  int _previewRequestId = 0;

  // Bounded LRU Cache for previews (max 20 entries) to make image switching instantaneous
  static const int _maxCacheEntries = 20;
  final Map<String, Uint8List> _previewCache = {};
  final Map<String, Uint8List> _compareCache = {};

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
  String? get documentId => _documentId;
  String? get existingPdfPath => _existingPdfPath;
  bool get isEditingExisting => _isEditingExisting;
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

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  /// Currently visible preview bytes based on whether user is holding Compare button
  Uint8List? get displayedPreviewBytes =>
      _isComparing ? (_originalPreviewBytes ?? _activePreviewBytes) : _activePreviewBytes;

  String _buildCacheKey(DocumentPage page, {List<double>? customPoints}) {
    final pts = customPoints != null
        ? customPoints.map((p) => p.toStringAsFixed(3)).join(',')
        : page.corners.map((c) => '${c.x.toStringAsFixed(3)},${c.y.toStringAsFixed(3)}').join(',');
    return '${page.id}_${page.filterType}_${page.brightness.toStringAsFixed(2)}_${page.contrast.toStringAsFixed(2)}_${page.sharpness.toStringAsFixed(2)}_${page.highlights.toStringAsFixed(2)}_${page.shadows.toStringAsFixed(2)}_${page.exposure.toStringAsFixed(2)}_${page.saturation.toStringAsFixed(2)}_w${page.watermark.enabled ? page.watermark.text : ""}_b${page.border.enabled ? page.border.thickness : 0}_m${page.margins.hasMargins ? 1 : 0}_r${page.redactions.length}_e${page.eraseStrokes.length}_$pts';
  }

  void _cachePreview(String key, Uint8List bytes) {
    if (_previewCache.length >= _maxCacheEntries) {
      _previewCache.remove(_previewCache.keys.first);
    }
    _previewCache[key] = bytes;
  }

  void _pushUndoSnapshot(String description) {
    if (_pages.isEmpty) return;
    _undoStack.add(
      EditorHistorySnapshot(
        pages: _pages.map((p) => p.copyWith()).toList(),
        currentPageIndex: _currentPageIndex,
        description: description,
      ),
    );
    if (_undoStack.length > _maxHistoryDepth) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
    _persistRecoveryDraft();
    notifyListeners();
  }

  void undo() {
    if (!canUndo) return;
    final current = EditorHistorySnapshot(
      pages: _pages.map((p) => p.copyWith()).toList(),
      currentPageIndex: _currentPageIndex,
      description: 'current',
    );
    _redoStack.add(current);

    final snapshot = _undoStack.removeLast();
    _pages = snapshot.pages.map((p) => p.copyWith()).toList();
    _currentPageIndex = snapshot.currentPageIndex.clamp(0, _pages.isNotEmpty ? _pages.length - 1 : 0);
    _syncCornerPoints();
    _triggerPreviewUpdate();
    _persistRecoveryDraft();
    notifyListeners();
  }

  void redo() {
    if (!canRedo) return;
    final current = EditorHistorySnapshot(
      pages: _pages.map((p) => p.copyWith()).toList(),
      currentPageIndex: _currentPageIndex,
      description: 'current',
    );
    _undoStack.add(current);

    final snapshot = _redoStack.removeLast();
    _pages = snapshot.pages.map((p) => p.copyWith()).toList();
    _currentPageIndex = snapshot.currentPageIndex.clamp(0, _pages.isNotEmpty ? _pages.length - 1 : 0);
    _syncCornerPoints();
    _triggerPreviewUpdate();
    _persistRecoveryDraft();
    notifyListeners();
  }

  void setIsComparing(bool val) {
    if (_isComparing != val) {
      _isComparing = val;
      notifyListeners();
    }
  }

  void setDocumentTitle(String title) {
    _documentTitle = title;
    _persistRecoveryDraft();
    notifyListeners();
  }

  // ─── Session Recovery Draft Persistence ────────────────────────────────
  static const String _draftFileName = 'session_recovery_draft.json';

  Future<void> _persistRecoveryDraft() async {
    if (_pages.isEmpty) return;
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final draftFile = File('${appDir.path}/$_draftFileName');
      final data = {
        'version': 1,
        'timestamp': DateTime.now().toIso8601String(),
        'documentTitle': _documentTitle,
        'documentId': _documentId,
        'existingPdfPath': _existingPdfPath,
        'isEditingExisting': _isEditingExisting,
        'currentPageIndex': _currentPageIndex,
        'pages': _pages.map((p) => p.toJson()).toList(),
      };
      await draftFile.writeAsString(jsonEncode(data), flush: true);
    } catch (e) {
      debugPrint('[DocuRay Draft] Persistence error: $e');
    }
  }

  Future<void> discardRecoveryDraft() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final draftFile = File('${appDir.path}/$_draftFileName');
      if (await draftFile.exists()) {
        await draftFile.delete();
      }
    } catch (_) {}
  }

  static Future<void> discardRecoveryDraftStatic() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final draftFile = File('${appDir.path}/$_draftFileName');
      if (await draftFile.exists()) {
        await draftFile.delete();
      }
    } catch (_) {}
  }

  static Future<bool> hasRecoveryDraft() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final draftFile = File('${appDir.path}/$_draftFileName');
      if (!await draftFile.exists()) return false;
      final content = await draftFile.readAsString();
      if (content.trim().isEmpty) return false;
      final data = jsonDecode(content) as Map<String, dynamic>;
      final pagesList = data['pages'] as List<dynamic>?;
      if (pagesList == null || pagesList.isEmpty) return false;

      // Verify at least one page's original or processed image exists on disk
      for (final item in pagesList) {
        final pageJson = item as Map<String, dynamic>;
        final orig = pageJson['originalImagePath'] as String?;
        final proc = pageJson['processedImagePath'] as String?;
        if (orig != null && File(orig).existsSync()) return true;
        if (proc != null && File(proc).existsSync()) return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>?> getRecoveryDraftInfo() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final draftFile = File('${appDir.path}/$_draftFileName');
      if (!await draftFile.exists()) return null;
      final content = await draftFile.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      final pagesList = data['pages'] as List<dynamic>? ?? [];
      return {
        'title': data['documentTitle'] as String? ?? 'Untitled Scan',
        'pageCount': pagesList.length,
        'timestamp': data['timestamp'] as String? ?? '',
      };
    } catch (_) {
      return null;
    }
  }

  Future<bool> restoreFromRecoveryDraft() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final draftFile = File('${appDir.path}/$_draftFileName');
      if (!await draftFile.exists()) return false;
      final content = await draftFile.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;

      _documentTitle = data['documentTitle'] as String? ?? 'Restored Scan';
      _documentId = data['documentId'] as String?;
      _existingPdfPath = data['existingPdfPath'] as String?;
      _isEditingExisting = data['isEditingExisting'] as bool? ?? false;
      _currentPageIndex = (data['currentPageIndex'] as num?)?.toInt() ?? 0;

      final pagesList = data['pages'] as List<dynamic>? ?? [];
      _pages = pagesList.map((p) => DocumentPage.fromJson(p as Map<String, dynamic>)).toList();

      if (_currentPageIndex >= _pages.length) {
        _currentPageIndex = 0;
      }

      _undoStack.clear();
      _redoStack.clear();
      _syncCornerPoints();
      _triggerPreviewUpdate();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[DocuRay Draft] Restoration error: $e');
      return false;
    }
  }

  DocumentPage? get currentPage {
    if (_pages.isEmpty || _currentPageIndex < 0 || _currentPageIndex >= _pages.length) {
      return null;
    }
    return _pages[_currentPageIndex];
  }

  void initializeWithPages(
    List<DocumentPage> initialPages, {
    String? title,
    String? documentId,
    String? existingPdfPath,
    SettingsProvider? settings,
  }) {
    _documentId = documentId;
    _existingPdfPath = existingPdfPath;
    _isEditingExisting = documentId != null;
    _previewCache.clear();
    _compareCache.clear();
    _undoStack.clear();
    _redoStack.clear();
    _previewRequestId++;

    if (initialPages.isNotEmpty) {
      // If creating a fresh scan session and settings provided, apply remembered preferences
      if (documentId == null && settings != null) {
        _pages = initialPages.map((p) => settings.applyPreferencesToNewPage(p)).toList();
      } else {
        _pages = List.from(initialPages);
      }
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
    _persistRecoveryDraft();
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
    _documentId = null;
    _existingPdfPath = null;
    _isEditingExisting = false;
    _previewCache.clear();
    _compareCache.clear();
    _undoStack.clear();
    _redoStack.clear();
    _previewRequestId++;
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
      if (_currentPageIndex == index && _activePreviewBytes != null) return;
      _currentPageIndex = index;
      _syncCornerPoints();

      final page = _pages[index];
      final key = _buildCacheKey(page);

      if (_previewCache.containsKey(key)) {
        _activePreviewBytes = _previewCache[key];
        _originalPreviewBytes = _compareCache[page.id];
        _isProcessingPreview = false;
        notifyListeners();
      } else {
        _activePreviewBytes = null;
        _originalPreviewBytes = null;
        notifyListeners();
        _triggerPreviewUpdate();
      }
    }
  }

  void setActiveTool(EditorActiveTool tool) {
    if (tool == EditorActiveTool.undo) {
      undo();
      return;
    }
    if (tool == EditorActiveTool.redo) {
      redo();
      return;
    }

    final previous = _activeTool;
    _activeTool = _activeTool == tool ? EditorActiveTool.none : tool;

    // If closing crop tool, refresh preview with new corners
    if (previous == EditorActiveTool.crop && _activeTool != EditorActiveTool.crop) {
      _triggerPreviewUpdate();
    }

    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 1. CROP
  // ---------------------------------------------------------------------------
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

  void updateEdge(int edgeIndex, Offset deltaNormalized) {
    if (_cornerPoints.length < 4) return;

    switch (edgeIndex) {
      case 0:
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
      case 1:
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
      case 2:
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
      case 3:
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

  void resetCrop() {
    _pushUndoSnapshot('Auto Crop');
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

  void resetToFullFrame() {
    _pushUndoSnapshot('Full Frame');
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

  void straightenCrop() {
    if (_cornerPoints.length == 4) {
      _pushUndoSnapshot('Straighten Crop');
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

  // ---------------------------------------------------------------------------
  // 2. ROTATE (Apply to All supported)
  // ---------------------------------------------------------------------------
  void rotateCurrentPage({bool clockwise = true}) {
    if (currentPage != null) {
      _pushUndoSnapshot('Rotate Page');
      final currentRotation = currentPage!.rotationDegrees;
      final delta = clockwise ? 90 : -90;
      _pages[_currentPageIndex] = currentPage!.copyWith(
        rotationDegrees: (currentRotation + delta + 360) % 360,
      );
      notifyListeners();
    }
  }

  void rotatePageAt(int index, {int deltaDegrees = 90}) {
    if (index >= 0 && index < _pages.length) {
      _pushUndoSnapshot('Rotate Page');
      final p = _pages[index];
      _pages[index] = p.copyWith(rotationDegrees: (p.rotationDegrees + deltaDegrees + 360) % 360);
      notifyListeners();
    }
  }

  void applyRotateToAll(int deltaDegrees) {
    if (_pages.isEmpty) return;
    _pushUndoSnapshot('Apply Rotation to All');
    for (int i = 0; i < _pages.length; i++) {
      final p = _pages[i];
      _pages[i] = p.copyWith(rotationDegrees: (p.rotationDegrees + deltaDegrees + 360) % 360);
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 3. FILTER (Apply to All supported)
  // ---------------------------------------------------------------------------
  void setFilter(String filterType) {
    if (currentPage != null) {
      _pushUndoSnapshot('Set Filter: $filterType');
      _pages[_currentPageIndex] = currentPage!.copyWith(filterType: filterType);
      _triggerPreviewUpdate();
      notifyListeners();
    }
  }

  void applyFilterToAll(String filterType) {
    if (_pages.isEmpty) return;
    _pushUndoSnapshot('Apply Filter to All');
    for (int i = 0; i < _pages.length; i++) {
      _pages[i] = _pages[i].copyWith(filterType: filterType);
    }
    _triggerPreviewUpdate();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 4. ADJUST (Apply to All supported)
  // ---------------------------------------------------------------------------
  void setAdjustments({
    double? brightness,
    double? contrast,
    double? sharpness,
    double? highlights,
    double? shadows,
    double? exposure,
    double? saturation,
  }) {
    if (currentPage != null) {
      _pushUndoSnapshot('Adjust Image');
      _pages[_currentPageIndex] = currentPage!.copyWith(
        brightness: brightness ?? currentPage!.brightness,
        contrast: contrast ?? currentPage!.contrast,
        sharpness: sharpness ?? currentPage!.sharpness,
        highlights: highlights ?? currentPage!.highlights,
        shadows: shadows ?? currentPage!.shadows,
        exposure: exposure ?? currentPage!.exposure,
        saturation: saturation ?? currentPage!.saturation,
      );
      _adjustmentDebounce?.cancel();
      _adjustmentDebounce = Timer(const Duration(milliseconds: 90), () {
        _triggerPreviewUpdate();
      });
      notifyListeners();
    }
  }

  void resetIndividualAdjustment(String key) {
    if (currentPage == null) return;
    _pushUndoSnapshot('Reset Adjustment: $key');
    switch (key) {
      case 'brightness':
        _pages[_currentPageIndex] = currentPage!.copyWith(brightness: 0.0);
        break;
      case 'contrast':
        _pages[_currentPageIndex] = currentPage!.copyWith(contrast: 0.0);
        break;
      case 'sharpness':
        _pages[_currentPageIndex] = currentPage!.copyWith(sharpness: 0.0);
        break;
      case 'highlights':
        _pages[_currentPageIndex] = currentPage!.copyWith(highlights: 0.0);
        break;
      case 'shadows':
        _pages[_currentPageIndex] = currentPage!.copyWith(shadows: 0.0);
        break;
      case 'exposure':
        _pages[_currentPageIndex] = currentPage!.copyWith(exposure: 0.0);
        break;
      case 'saturation':
        _pages[_currentPageIndex] = currentPage!.copyWith(saturation: 0.0);
        break;
    }
    _triggerPreviewUpdate();
    notifyListeners();
  }

  void resetAllAdjustments() {
    if (currentPage == null) return;
    _pushUndoSnapshot('Reset All Adjustments');
    _pages[_currentPageIndex] = currentPage!.copyWith(
      brightness: 0.0,
      contrast: 0.0,
      sharpness: 0.0,
      highlights: 0.0,
      shadows: 0.0,
      exposure: 0.0,
      saturation: 0.0,
    );
    _triggerPreviewUpdate();
    notifyListeners();
  }

  void applyAdjustmentsToAll({
    double? brightness,
    double? contrast,
    double? sharpness,
    double? highlights,
    double? shadows,
    double? exposure,
    double? saturation,
  }) {
    if (_pages.isEmpty) return;
    _pushUndoSnapshot('Apply Adjustments to All');
    final cur = currentPage;
    final b = brightness ?? cur?.brightness ?? 0.0;
    final c = contrast ?? cur?.contrast ?? 0.0;
    final s = sharpness ?? cur?.sharpness ?? 0.0;
    final h = highlights ?? cur?.highlights ?? 0.0;
    final sh = shadows ?? cur?.shadows ?? 0.0;
    final exp = exposure ?? cur?.exposure ?? 0.0;
    final sat = saturation ?? cur?.saturation ?? 0.0;

    for (int i = 0; i < _pages.length; i++) {
      _pages[i] = _pages[i].copyWith(
        brightness: b,
        contrast: c,
        sharpness: s,
        highlights: h,
        shadows: sh,
        exposure: exp,
        saturation: sat,
      );
    }
    _triggerPreviewUpdate();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 5. RETAKE
  // ---------------------------------------------------------------------------
  void replacePageWithCapture(int index, DocumentPage newPage) {
    if (index >= 0 && index < _pages.length) {
      _pushUndoSnapshot('Retake Page ${index + 1}');
      _pages[index] = newPage.copyWith(
        id: _pages[index].id,
        pageNumber: index + 1,
      );
      _syncCornerPoints();
      _triggerPreviewUpdate();
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // 6. ERASE
  // ---------------------------------------------------------------------------
  void addEraseStroke(EraseStroke stroke) {
    if (currentPage == null) return;
    _pushUndoSnapshot('Erase Stroke');
    final updated = List<EraseStroke>.from(currentPage!.eraseStrokes)..add(stroke);
    _pages[_currentPageIndex] = currentPage!.copyWith(eraseStrokes: updated);
    _triggerPreviewUpdate();
    notifyListeners();
  }

  void clearEraseStrokes() {
    if (currentPage == null) return;
    _pushUndoSnapshot('Clear Erase');
    _pages[_currentPageIndex] = currentPage!.copyWith(eraseStrokes: const []);
    _triggerPreviewUpdate();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 7. ANNOTATE
  // ---------------------------------------------------------------------------
  void addAnnotation(AnnotationElement element) {
    if (currentPage == null) return;
    _pushUndoSnapshot('Add Annotation');
    final updated = List<AnnotationElement>.from(currentPage!.annotations)..add(element);
    _pages[_currentPageIndex] = currentPage!.copyWith(annotations: updated);
    notifyListeners();
  }

  void removeAnnotation(String id) {
    if (currentPage == null) return;
    _pushUndoSnapshot('Remove Annotation');
    final updated = currentPage!.annotations.where((a) => a.id != id).toList();
    _pages[_currentPageIndex] = currentPage!.copyWith(annotations: updated);
    notifyListeners();
  }

  void clearAnnotations() {
    if (currentPage == null) return;
    _pushUndoSnapshot('Clear Annotations');
    _pages[_currentPageIndex] = currentPage!.copyWith(annotations: const []);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 8. WATERMARK (Apply to All supported)
  // ---------------------------------------------------------------------------
  void updateWatermark(WatermarkConfig watermark) {
    if (currentPage == null) return;
    _pushUndoSnapshot('Update Watermark');
    _pages[_currentPageIndex] = currentPage!.copyWith(watermark: watermark);
    notifyListeners();
  }

  void applyWatermarkToAll(WatermarkConfig watermark) {
    if (_pages.isEmpty) return;
    _pushUndoSnapshot('Apply Watermark to All');
    for (int i = 0; i < _pages.length; i++) {
      _pages[i] = _pages[i].copyWith(watermark: watermark);
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 9. REDACT (Genuine Redaction)
  // ---------------------------------------------------------------------------
  void addRedaction(RedactionRect redaction) {
    if (currentPage == null) return;
    _pushUndoSnapshot('Add Redaction');
    final updated = List<RedactionRect>.from(currentPage!.redactions)..add(redaction);
    _pages[_currentPageIndex] = currentPage!.copyWith(redactions: updated);
    notifyListeners();
  }

  void removeRedaction(String id) {
    if (currentPage == null) return;
    _pushUndoSnapshot('Remove Redaction');
    final updated = currentPage!.redactions.where((r) => r.id != id).toList();
    _pages[_currentPageIndex] = currentPage!.copyWith(redactions: updated);
    notifyListeners();
  }

  void clearRedactions() {
    if (currentPage == null) return;
    _pushUndoSnapshot('Clear Redactions');
    _pages[_currentPageIndex] = currentPage!.copyWith(redactions: const []);
    notifyListeners();
  }

  void setRedactions(List<RedactionRect> redactions) {
    if (currentPage == null) return;
    _pages[_currentPageIndex] = currentPage!.copyWith(redactions: redactions);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 10. RESIZE (Apply to All supported)
  // ---------------------------------------------------------------------------
  void updateResize(PageResizeConfig resize) {
    if (currentPage == null) return;
    _pushUndoSnapshot('Resize Page');
    _pages[_currentPageIndex] = currentPage!.copyWith(resize: resize);
    notifyListeners();
  }

  void applyResizeToAll(PageResizeConfig resize) {
    if (_pages.isEmpty) return;
    _pushUndoSnapshot('Apply Resize to All');
    for (int i = 0; i < _pages.length; i++) {
      _pages[i] = _pages[i].copyWith(resize: resize);
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 11. MARGINS (Apply to All supported)
  // ---------------------------------------------------------------------------
  void updateMargins(PageMargins margins) {
    if (currentPage == null) return;
    _pushUndoSnapshot('Update Margins');
    _pages[_currentPageIndex] = currentPage!.copyWith(margins: margins);
    notifyListeners();
  }

  void applyMarginsToAll(PageMargins margins) {
    if (_pages.isEmpty) return;
    _pushUndoSnapshot('Apply Margins to All');
    for (int i = 0; i < _pages.length; i++) {
      _pages[i] = _pages[i].copyWith(margins: margins);
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 12. BORDER (Apply to All supported)
  // ---------------------------------------------------------------------------
  void updateBorder(PageBorder border) {
    if (currentPage == null) return;
    _pushUndoSnapshot('Update Border');
    _pages[_currentPageIndex] = currentPage!.copyWith(border: border);
    notifyListeners();
  }

  void applyBorderToAll(PageBorder border) {
    if (_pages.isEmpty) return;
    _pushUndoSnapshot('Apply Border to All');
    for (int i = 0; i < _pages.length; i++) {
      _pages[i] = _pages[i].copyWith(border: border);
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 13. REORDER PAGES
  // ---------------------------------------------------------------------------
  void reorderPages(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _pages.length || newIndex < 0 || newIndex > _pages.length) return;
    _pushUndoSnapshot('Reorder Pages');
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
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 16. RESET
  // ---------------------------------------------------------------------------
  void resetCurrentPage() {
    final page = currentPage;
    if (page == null) return;
    _pushUndoSnapshot('Reset Page ${page.pageNumber}');

    final corners = (page.autoDetectedCorners != null && page.autoDetectedCorners!.length == 4)
        ? page.autoDetectedCorners!
        : const [
            CornerPoint(0.0, 0.0),
            CornerPoint(1.0, 0.0),
            CornerPoint(1.0, 1.0),
            CornerPoint(0.0, 1.0),
          ];

    _pages[_currentPageIndex] = DocumentPage(
      id: page.id,
      pageNumber: page.pageNumber,
      originalImagePath: page.originalImagePath,
      autoDetectedCorners: page.autoDetectedCorners,
      corners: corners,
      rotationDegrees: 0,
      filterType: 'original',
      brightness: 0.0,
      contrast: 0.0,
      sharpness: 0.0,
      highlights: 0.0,
      shadows: 0.0,
      exposure: 0.0,
      saturation: 0.0,
      eraseStrokes: const [],
      annotations: const [],
      watermark: const WatermarkConfig(enabled: false),
      redactions: const [],
      resize: const PageResizeConfig(),
      margins: const PageMargins(),
      border: const PageBorder(enabled: false),
    );

    _syncCornerPoints();
    _triggerPreviewUpdate();
    _persistRecoveryDraft();
    notifyListeners();
  }

  void addPage(DocumentPage page) {
    _pushUndoSnapshot('Add Page');
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
    _persistRecoveryDraft();
    notifyListeners();
  }

  void deletePageAt(int index) {
    if (_pages.length <= 1) return;
    _pushUndoSnapshot('Delete Page ${index + 1}');
    _pages.removeAt(index);
    for (int i = 0; i < _pages.length; i++) {
      _pages[i] = _pages[i].copyWith(pageNumber: i + 1);
    }
    if (_currentPageIndex >= _pages.length) {
      _currentPageIndex = _pages.length - 1;
    }
    _syncCornerPoints();
    _triggerPreviewUpdate();
    _persistRecoveryDraft();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Preview Generation Pipeline
  // ---------------------------------------------------------------------------
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

    final targetPageIndex = _currentPageIndex;
    final targetPageId = page.id;
    final currentRequestId = ++_previewRequestId;

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

    final cacheKey = _buildCacheKey(page, customPoints: points);

    if (_previewCache.containsKey(cacheKey)) {
      if (currentRequestId == _previewRequestId && _currentPageIndex == targetPageIndex) {
        _activePreviewBytes = _previewCache[cacheKey];
        _originalPreviewBytes = _compareCache[targetPageId];
        _isProcessingPreview = false;
        notifyListeners();
      }
      return;
    }

    _isProcessingPreview = true;
    notifyListeners();

    try {
      if (NativeScannerService.isNativeSupported) {
        final previewOut = await NativeScannerService.processPage(
          page.originalImagePath!,
          points: points,
          degrees: 0,
          filter: page.filterType,
          brightness: _toNativeBrightness(page.brightness),
          contrast: _toNativeContrast(page.contrast),
          sharpness: page.sharpness,
          maxDimension: 960,
          quality: 82,
        );

        if (currentRequestId != _previewRequestId || _currentPageIndex != targetPageIndex) {
          return;
        }

        if (previewOut != null && await File(previewOut).exists()) {
          final bytes = await File(previewOut).readAsBytes();
          _cachePreview(cacheKey, bytes);
          _activePreviewBytes = bytes;
        }

        if (!_compareCache.containsKey(targetPageId)) {
          final originalOut = await NativeScannerService.processPage(
            page.originalImagePath!,
            points: points,
            degrees: 0,
            filter: 'original',
            brightness: 0.0,
            contrast: 0.0,
            sharpness: 0.0,
            maxDimension: 960,
            quality: 82,
          );
          if (originalOut != null && await File(originalOut).exists()) {
            final origBytes = await File(originalOut).readAsBytes();
            _compareCache[targetPageId] = origBytes;
            if (currentRequestId == _previewRequestId && _currentPageIndex == targetPageIndex) {
              _originalPreviewBytes = origBytes;
            }
          }
        } else {
          _originalPreviewBytes = _compareCache[targetPageId];
        }
        return;
      }

      // Dart fallback
      final bytes = await file.readAsBytes();
      var rawImg = img.decodeImage(bytes);
      if (rawImg != null) {
        rawImg = img.bakeOrientation(rawImg);
        if (rawImg.width > 960 || rawImg.height > 960) {
          rawImg = img.copyResize(
            rawImg,
            width: rawImg.width > rawImg.height ? 960 : null,
            height: rawImg.height >= rawImg.width ? 960 : null,
          );
        }

        final warped = PerspectiveTransform.warp(source: rawImg, corners: corners);
        final origBytes = Uint8List.fromList(img.encodeJpg(warped, quality: 82));
        _compareCache[targetPageId] = origBytes;

        final enhanced = ImageEnhancer.process(
          source: warped,
          filterType: page.filterType,
          brightness: page.brightness,
          contrast: page.contrast,
          sharpness: page.sharpness,
          highlights: page.highlights,
          shadows: page.shadows,
          exposure: page.exposure,
          saturation: page.saturation,
        );

        final enhancedBytes = Uint8List.fromList(img.encodeJpg(enhanced, quality: 82));

        if (currentRequestId != _previewRequestId || _currentPageIndex != targetPageIndex) {
          return;
        }

        _cachePreview(cacheKey, enhancedBytes);
        _activePreviewBytes = enhancedBytes;
        _originalPreviewBytes = origBytes;
      }
    } catch (e) {
      debugPrint('[DocuRay] Preview generation error: $e');
    } finally {
      if (currentRequestId == _previewRequestId) {
        _isProcessingPreview = false;
        notifyListeners();
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Optimized PDF Export Pipeline
  // ---------------------------------------------------------------------------
  Future<Document> saveDocument({
    String? title,
    PdfExportQuality exportQuality = PdfExportQuality.standard,
    bool saveAsCopy = false,
  }) async {
    if (_isSaving) {
      throw StateError('Export already in progress');
    }
    _isSaving = true;
    notifyListeners();

    final totalSw = Stopwatch()..start();

    try {
      final effectiveTitle = (title != null && title.trim().isNotEmpty)
          ? title.trim()
          : (_documentTitle.trim().isNotEmpty
              ? _documentTitle.trim()
              : 'Scan ${DateTime.now().millisecondsSinceEpoch}');

      final bool isUpdatingExisting = _isEditingExisting && !saveAsCopy && _documentId != null;
      final docId = isUpdatingExisting ? _documentId! : 'doc_${DateTime.now().millisecondsSinceEpoch}';

      final appDir = await getApplicationDocumentsDirectory();
      final docDir = Directory('${appDir.path}/documents/$docId');
      if (!await docDir.exists()) {
        await docDir.create(recursive: true);
      }

      final processedPages = <DocumentPage>[];
      final useNative = NativeScannerService.isNativeSupported;

      for (int i = 0; i < _pages.length; i++) {
        final pageSw = Stopwatch()..start();
        final p = _pages[i];
        final pageNum = i + 1;

        if (p.originalImagePath != null && await File(p.originalImagePath!).exists()) {
          final origFile = File(p.originalImagePath!);
          final origExt = p.originalImagePath!.split('.').last.toLowerCase();
          final ext = (origExt == 'jpg' || origExt == 'jpeg' || origExt == 'png') ? origExt : 'jpg';
          final permOrigPath = '${docDir.path}/page_${pageNum}_original.$ext';

          if (origFile.path != permOrigPath) {
            await origFile.copy(permOrigPath);
          }

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

          bool processedWithNative = false;
          if (useNative) {
            try {
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
                processedWithNative = true;
              }
            } catch (e) {
              debugPrint('[DocuRay] Native export failed: $e, falling back to Dart engine');
            }
          }

          if (!processedWithNative) {
            // Full-resolution Dart processing fallback
            final rawBytes = await File(permOrigPath).readAsBytes();
            var fullImg = img.decodeImage(rawBytes);

            if (fullImg != null) {
              fullImg = img.bakeOrientation(fullImg);
              var processed = isFullPage
                  ? fullImg
                  : PerspectiveTransform.warp(source: fullImg, corners: corners);
              if (p.rotationDegrees != 0) {
                processed = img.copyRotate(processed, angle: p.rotationDegrees);
              }
              final needsEnhance = p.filterType.toLowerCase() != 'original' ||
                  p.brightness != 0 ||
                  p.contrast != 0 ||
                  p.sharpness != 0 ||
                  p.highlights != 0 ||
                  p.shadows != 0 ||
                  p.exposure != 0 ||
                  p.saturation != 0;
              if (needsEnhance) {
                processed = ImageEnhancer.process(
                  source: processed,
                  filterType: p.filterType,
                  brightness: p.brightness,
                  contrast: p.contrast,
                  sharpness: p.sharpness,
                  highlights: p.highlights,
                  shadows: p.shadows,
                  exposure: p.exposure,
                  saturation: p.saturation,
                );
              }

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

          // Burn permanent redactions and erase strokes into image bitmap
          if (p.redactions.isNotEmpty || p.eraseStrokes.isNotEmpty) {
            final procFile = File(processedPath);
            if (await procFile.exists()) {
              final pBytes = await procFile.readAsBytes();
              var procImg = img.decodeImage(pBytes);
              if (procImg != null) {
                // Redactions: permanently zero out pixel values
                for (final r in p.redactions) {
                  final rx = (r.left * procImg.width).round().clamp(0, procImg.width - 1);
                  final ry = (r.top * procImg.height).round().clamp(0, procImg.height - 1);
                  final rw = (r.width * procImg.width).round().clamp(1, procImg.width - rx);
                  final rh = (r.height * procImg.height).round().clamp(1, procImg.height - ry);
                  img.fillRect(
                    procImg,
                    x1: rx,
                    y1: ry,
                    x2: rx + rw,
                    y2: ry + rh,
                    color: img.ColorRgb8(0, 0, 0),
                  );
                }
                // Erase strokes: paint white paper background
                for (final stroke in p.eraseStrokes) {
                  for (final pt in stroke.points) {
                    final px = (pt.dx * procImg.width).round().clamp(0, procImg.width - 1);
                    final py = (pt.dy * procImg.height).round().clamp(0, procImg.height - 1);
                    final radius = (stroke.strokeWidth * (procImg.width / 400.0)).round().clamp(2, 60);
                    img.fillCircle(
                      procImg,
                      x: px,
                      y: py,
                      radius: radius,
                      color: img.ColorRgb8(255, 255, 255),
                    );
                  }
                }
                await procFile.writeAsBytes(img.encodeJpg(procImg, quality: exportQuality.jpegQuality));
              }
            }
          }

          // Generate thumbnail fast from preview cache or downscale
          final thumbPath = '${docDir.path}/page_${pageNum}_thumb.jpg';
          try {
            final cacheKey = _buildCacheKey(p);
            if (_previewCache.containsKey(cacheKey)) {
              final cachedBytes = _previewCache[cacheKey]!;
              final previewImg = img.decodeJpg(cachedBytes);
              if (previewImg != null) {
                final thumbImg = img.copyResize(previewImg, width: 240);
                await File(thumbPath).writeAsBytes(img.encodeJpg(thumbImg, quality: 75));
              }
            } else {
              final procBytes = await File(processedPath).readAsBytes();
              final procImg = img.decodeImage(procBytes);
              if (procImg != null) {
                final thumbImg = img.copyResize(procImg, width: 240);
                await File(thumbPath).writeAsBytes(img.encodeJpg(thumbImg, quality: 75));
              }
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

          debugPrint('[DocuRay Export Profiler] Page $pageNum ($docId) processed in ${pageSw.elapsedMilliseconds} ms');
        } else {
          processedPages.add(p.copyWith(pageNumber: pageNum));
        }
      }

      // Fast multi-page PDF generation with direct JPEG embedding
      final pdfSw = Stopwatch()..start();
      final safeFileName = effectiveTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final targetPdfPath = '${docDir.path}/$safeFileName.pdf';
      final tempPdfPath = '${docDir.path}/$safeFileName.pdf.tmp';

      final tempPdfFile = await PdfGeneratorService.generatePdf(
        pages: processedPages,
        outputPath: tempPdfPath,
        documentTitle: effectiveTitle,
        quality: exportQuality,
        isPreCompressed: true, // Blazingly fast direct embedding
      );

      if (!await tempPdfFile.exists() || await tempPdfFile.length() == 0) {
        throw FileSystemException('Generated PDF file is empty or missing.', tempPdfPath);
      }

      if (_existingPdfPath != null && _existingPdfPath != targetPdfPath) {
        final oldFile = File(_existingPdfPath!);
        if (await oldFile.exists()) {
          try {
            await oldFile.delete();
          } catch (_) {}
        }
      }

      final targetFile = File(targetPdfPath);
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await tempPdfFile.rename(targetPdfPath);

      final finalPdfFile = File(targetPdfPath);
      _lastExportSizeBytes = await finalPdfFile.length();
      _existingPdfPath = targetPdfPath;
      _documentId = docId;
      _isEditingExisting = true;

      final primaryThumbPath = processedPages.isNotEmpty ? processedPages.first.thumbnailPath : null;

      final existingDoc = isUpdatingExisting
          ? await LocalDocumentRepository.instance.getDocumentById(docId)
          : null;

      final document = Document(
        id: docId,
        title: effectiveTitle,
        pages: processedPages,
        createdAt: existingDoc?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
        pdfPath: targetPdfPath,
        thumbnailPath: primaryThumbPath,
        format: DocumentFormat.pdf,
        isFavorite: existingDoc?.isFavorite ?? false,
        folderId: existingDoc?.folderId,
        syncMetadata: existingDoc?.syncMetadata ?? const SyncMetadata(status: SyncStatus.notSynced),
      );

      await LocalDocumentRepository.instance.saveDocument(document);
      await discardRecoveryDraft();

      debugPrint('[DocuRay Export Profiler] PDF generated in ${pdfSw.elapsedMilliseconds} ms');
      debugPrint('[DocuRay Export Profiler] Total export completed in ${totalSw.elapsedMilliseconds} ms (${processedPages.length} pages, size: $lastExportSizeFormatted)');

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
