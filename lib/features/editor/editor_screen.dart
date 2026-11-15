import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/providers/editor_provider.dart';
import '../../core/providers/documents_provider.dart';
import '../../core/providers/scanner_provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/services/pdf_generator_service.dart';
import '../../core/services/google_drive_service.dart';
import '../../core/routing/app_router.dart';
import '../../core/widgets/document_thumbnail.dart';
import '../../models/models.dart';
import 'widgets/editor_preview_overlay.dart';
import 'widgets/editor_tool_panels.dart';

/// Screen 6: Scan Result / Document Editor with real 4-point perspective warp preview,
/// draggable corners and edge handles, professional filters, adjustments, multi-page reordering,
/// hold-to-compare original, and real Small/Standard/High PDF export quality.
class EditorScreen extends StatefulWidget {
  final String? documentId;

  const EditorScreen({super.key, this.documentId});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final ScrollController _toolbarScrollController = ScrollController();
  double _eraseBrushSize = 15.0;
  AnnotationType _activeAnnotationType = AnnotationType.pen;
  Color _activeAnnotationColor = const Color(0xFFFF0000);
  double _activeAnnotationStrokeWidth = 3.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final editor = context.read<EditorProvider>();
      final docsProvider = context.read<DocumentsProvider>();

      if (widget.documentId != null) {
        final doc = docsProvider.getDocument(widget.documentId!);
        if (doc != null) {
          editor.initializeWithPages(
            doc.pages,
            title: doc.title,
            documentId: doc.id,
            existingPdfPath: doc.pdfPath,
          );
        }
      } else if (editor.pages.isEmpty && mounted) {
        // Discard stale or invalid navigation to editor without pages
        context.go(AppRouter.home);
        return;
      }

      final page = editor.currentPage;
      if (page != null && page.autoDetectedCorners == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No document detected. You can adjust crop corners manually.'),
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _toolbarScrollController.dispose();
    super.dispose();
  }

  Future<void> _onHomePressed(EditorProvider editor) async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave Editor?'),
        content: const Text(
          'Your current scan has not been saved as a PDF yet. Leaving will discard the pending session and return to Home.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Editing'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard & Leave'),
          ),
        ],
      ),
    );

    if (leave == true && mounted) {
      await editor.discardRecoveryDraft();
      editor.clearPages();
      if (!mounted) return;
      context.go(AppRouter.home);
    }
  }

  Future<void> _onSavePdf(EditorProvider editor) async {
    if (editor.pages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pages to save.')),
      );
      return;
    }

    if (editor.isSaving) return;

    final settings = context.read<SettingsProvider>();
    final initialQuality = PdfExportQuality.fromString(settings.defaultPdfQuality);

    // Prompt user with Export Quality selector (Small, Standard, High)
    final selection = await showModalBottomSheet<_ExportSelection>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ExportQualitySheet(
        initialQuality: initialQuality,
        isEditingExisting: editor.isEditingExisting,
      ),
    );

    if (selection == null || !mounted) return;

    final docsProvider = context.read<DocumentsProvider>();

    var dialogDismissed = false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text('Saving PDF (${selection.quality.label})...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final savedDoc = await editor.saveDocument(
        exportQuality: selection.quality,
        saveAsCopy: selection.saveAsCopy,
      );
      await docsProvider.loadData();

      if (mounted) {
        if (!dialogDismissed) {
          dialogDismissed = true;
          Navigator.of(context, rootNavigator: true).pop(); // dismiss loading dialog safely
        }
        final sizeText = editor.lastExportSizeFormatted;
        final msg = sizeText.isNotEmpty
            ? 'Saved "${savedDoc.title}" ($sizeText)'
            : 'Saved "${savedDoc.title}" as PDF';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: AppColors.success,
          ),
        );

        // Automatic Google Drive backup if configured and enabled
        final settings = context.read<SettingsProvider>();
        if (settings.isDriveConnected && settings.driveAutoBackup) {
          GoogleDriveService.instance.backupSingleDocument(
            savedDoc,
            wifiOnly: settings.driveWifiOnly,
            includeMetadata: settings.driveIncludeMetadata,
          ).then((_) {
            docsProvider.loadData();
          }).catchError((_) {});
        }
        // Use push to maintain the editor on the back stack
        context.push('/viewer/${savedDoc.id}');
      }
    } catch (e) {
      if (mounted) {
        if (!dialogDismissed) {
          dialogDismissed = true;
          Navigator.of(context, rootNavigator: true).pop();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save document: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _onAddPage() {
    final scanner = context.read<ScannerProvider>();
    scanner.resumeCamera();
    context.push(AppRouter.scanner);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final editor = context.watch<EditorProvider>();
    final pageNumber = (editor.currentPageIndex + 1);
    final totalPages = editor.pages.isEmpty ? 1 : editor.pages.length;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.home_rounded),
          onPressed: () => _onHomePressed(editor),
          tooltip: 'Home',
        ),
        title: _buildEditableTitle(editor, isDark),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.tonal(
              onPressed: editor.isSaving ? null : () => _onSavePdf(editor),
              style: FilledButton.styleFrom(
                backgroundColor: isDark ? AppColors.darkPrimary : AppColors.primary,
                foregroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
              child: editor.isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text(
                      'Save PDF',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Subheader showing page index
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'Page $pageNumber of $totalPages',
              style: AppTypography.badge.copyWith(
                color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
              ),
            ),
          ),

          // 1. Center Page Preview with Draggable Corners & Edges
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      // Preview Image or Crop Canvas
                      _buildPreviewDisplay(editor, constraints, isDark),

                      // In Crop Mode: Floating Action Bar (Reset Auto, Full Frame, Straighten, Apply)
                      if (editor.activeTool == EditorActiveTool.crop)
                        Positioned(
                          top: 8,
                          left: 8,
                          right: 8,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.black87,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    textStyle: AppTypography.badge,
                                  ),
                                  icon: const Icon(Icons.auto_awesome_rounded, size: 14),
                                  label: const Text('Auto Crop'),
                                  onPressed: editor.resetCrop,
                                ),
                                const SizedBox(width: 6),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.black87,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    textStyle: AppTypography.badge,
                                  ),
                                  icon: const Icon(Icons.open_with_rounded, size: 14),
                                  label: const Text('Manual Crop'),
                                  onPressed: () {
                                    // Manual corner dragging is enabled
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Drag the corner handles or edge midpoints to adjust crop.'),
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(width: 6),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.black87,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    textStyle: AppTypography.badge,
                                  ),
                                  icon: const Icon(Icons.crop_free_rounded, size: 14),
                                  label: const Text('Full Frame'),
                                  onPressed: editor.resetToFullFrame,
                                ),
                                const SizedBox(width: 6),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.black87,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    textStyle: AppTypography.badge,
                                  ),
                                  icon: const Icon(Icons.crop_rotate_rounded, size: 14),
                                  label: const Text('Straighten'),
                                  onPressed: editor.straightenCrop,
                                ),
                                const SizedBox(width: 6),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isDark ? AppColors.darkPrimary : AppColors.primary,
                                    foregroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    textStyle: AppTypography.badge,
                                  ),
                                  icon: const Icon(Icons.check_rounded, size: 14),
                                  label: const Text('Apply'),
                                  onPressed: () => editor.setActiveTool(EditorActiveTool.none),
                                ),
                              ],
                            ),
                          ),
                        ),

                      // In Non-Crop Mode: Hold to Compare Original Floating Control
                      if (editor.activeTool != EditorActiveTool.crop && editor.displayedPreviewBytes != null)
                        Positioned(
                          top: 10,
                          right: 10,
                          child: GestureDetector(
                            onTapDown: (_) => editor.setIsComparing(true),
                            onTapUp: (_) => editor.setIsComparing(false),
                            onTapCancel: () => editor.setIsComparing(false),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: editor.isComparing
                                    ? AppColors.primary
                                    : Colors.black.withAlpha(160),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 4,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    editor.isComparing ? Icons.visibility_rounded : Icons.compare_rounded,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    editor.isComparing ? 'ORIGINAL' : 'COMPARE',
                                    style: AppTypography.badge.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                      // Processing Spinner indicator
                      if (editor.isProcessingPreview)
                        Positioned(
                          bottom: 12,
                          right: 12,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),

          // 2. Active Tool Drawer / Panel
          if (_buildActiveToolDrawer(editor, isDark) != null)
            _buildActiveToolDrawer(editor, isDark)!,

          // 3. Multi-Page Thumbnail Strip & Add Page CTA
          _buildMultiPageStrip(editor, isDark),

          // 4. Bottom Toolbar (16 tools in exact order)
          _buildBottomToolbar(editor, isDark),
        ],
      ),
    );
  }

  Widget _buildEditableTitle(EditorProvider editor, bool isDark) {
    return GestureDetector(
      onTap: () async {
        final controller = TextEditingController(text: editor.documentTitle);
        final newTitle = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Rename Document'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Document Name',
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                child: const Text('Save'),
              ),
            ],
          ),
        );
        if (newTitle != null && newTitle.isNotEmpty) {
          editor.setDocumentTitle(newTitle);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isDark ? Colors.white10 : Colors.black.withAlpha(10),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                editor.documentTitle.isNotEmpty ? editor.documentTitle : 'Scanned Document',
                style: AppTypography.buttonSmall.copyWith(
                  color: isDark ? AppColors.darkText : AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.edit_outlined,
              size: 14,
              color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewDisplay(EditorProvider editor, BoxConstraints constraints, bool isDark) {
    final page = editor.currentPage;

    // In crop tool mode: show original image with fitted aspect ratio
    // overlaying the exact 4 draggable corner and edge handles.
    if (editor.activeTool == EditorActiveTool.crop) {
      if (page?.originalImagePath != null && File(page!.originalImagePath!).existsSync()) {
        final pageAspect = page.aspectRatio;
        final maxW = constraints.maxWidth * 0.95;
        final maxH = constraints.maxHeight * 0.95;
        final boxAspect = maxW / maxH;

        double renderW, renderH;
        if (pageAspect > boxAspect) {
          renderW = maxW;
          renderH = maxW / pageAspect;
        } else {
          renderH = maxH;
          renderW = maxH * pageAspect;
        }

        return SizedBox(
          width: renderW,
          height: renderH,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(page.originalImagePath!),
                  fit: BoxFit.fill,
                  width: renderW,
                  height: renderH,
                ),
              ),
              _InteractiveCornerOverlay(
                corners: editor.cornerPoints,
                isCropActive: true,
                onCornerMoved: (index, pos) {
                  editor.updateCornerPoint(index, pos);
                },
                onEdgeMoved: (edgeIndex, delta) {
                  editor.updateEdge(edgeIndex, delta);
                },
              ),
            ],
          ),
        );
      }
    }

    // In standard / filter / adjust mode: show warped & enhanced preview
    final previewBytes = editor.displayedPreviewBytes;
    if (previewBytes != null) {
      final turns = ((page?.rotationDegrees ?? 0) ~/ 90) % 4;
      final rawAspect = (page?.aspectRatio != null && page!.aspectRatio > 0)
          ? page.aspectRatio
          : 0.707;
      final pageAspect = (turns % 2 == 1) ? (1.0 / rawAspect) : rawAspect;
      final maxW = constraints.maxWidth * 0.92;
      final maxH = constraints.maxHeight * 0.94;
      final boxAspect = maxW / maxH;

      double renderW, renderH;
      if (pageAspect > boxAspect) {
        renderW = maxW;
        renderH = maxW / pageAspect;
      } else {
        renderH = maxH;
        renderW = maxH * pageAspect;
      }

      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(isDark ? 50 : 20),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: renderW,
            height: renderH,
            child: Stack(
              fit: StackFit.expand,
              children: [
                RotatedBox(
                  quarterTurns: turns,
                  child: Image.memory(
                    previewBytes,
                    fit: BoxFit.fill,
                    width: renderW,
                    height: renderH,
                  ),
                ),
                if (page != null)
                  EditorPreviewOverlay(
                    editor: editor,
                    page: page,
                    size: Size(renderW, renderH),
                    eraseBrushSize: _eraseBrushSize,
                    activeAnnotationType: _activeAnnotationType,
                    activeAnnotationColor: _activeAnnotationColor,
                    activeAnnotationStrokeWidth: _activeAnnotationStrokeWidth,
                  ),
              ],
            ),
          ),
        ),
      );
    }

    // Fallback: document thumbnail
    return DocumentThumbnail(
      pageCount: 1,
      width: constraints.maxWidth * 0.82,
      height: constraints.maxHeight * 0.88,
      rotationDegrees: page?.rotationDegrees ?? 0,
      filterType: page?.filterType ?? 'auto',
      pageNumber: editor.currentPageIndex + 1,
      documentTitle: 'Scanned Page',
      imagePath: page?.processedImagePath ?? page?.originalImagePath,
    );
  }

  // Active Tool Drawer / Panel dispatcher
  Widget? _buildActiveToolDrawer(EditorProvider editor, bool isDark) {
    switch (editor.activeTool) {
      case EditorActiveTool.rotate:
        return RotateToolPanel(editor: editor);
      case EditorActiveTool.filter:
        return FilterToolPanel(editor: editor);
      case EditorActiveTool.adjust:
        return AdjustToolPanel(editor: editor);
      case EditorActiveTool.erase:
        return EraseToolPanel(
          editor: editor,
          brushSize: _eraseBrushSize,
          onBrushSizeChanged: (v) => setState(() => _eraseBrushSize = v),
        );
      case EditorActiveTool.annotate:
        return AnnotateToolPanel(
          editor: editor,
          activeType: _activeAnnotationType,
          activeColor: _activeAnnotationColor,
          strokeWidth: _activeAnnotationStrokeWidth,
          onTypeChanged: (t) => setState(() => _activeAnnotationType = t),
          onColorChanged: (c) => setState(() => _activeAnnotationColor = c),
          onStrokeWidthChanged: (w) => setState(() => _activeAnnotationStrokeWidth = w),
          onAddText: () => _showAddTextDialog(editor),
          onAddSignature: () => _showAddSignatureDialog(editor),
        );
      case EditorActiveTool.watermark:
        return WatermarkToolPanel(editor: editor);
      case EditorActiveTool.redact:
        return RedactToolPanel(editor: editor);
      case EditorActiveTool.resize:
        return ResizeToolPanel(editor: editor);
      case EditorActiveTool.margins:
        return MarginsToolPanel(editor: editor);
      case EditorActiveTool.border:
        return BorderToolPanel(editor: editor);
      case EditorActiveTool.reorder:
        return ReorderToolPanel(editor: editor);
      case EditorActiveTool.none:
      case EditorActiveTool.crop:
      case EditorActiveTool.retake:
      case EditorActiveTool.undo:
      case EditorActiveTool.redo:
      case EditorActiveTool.reset:
        return null;
    }
  }

  // Multi-Page Thumbnail Strip & Add Page CTA
  Widget _buildMultiPageStrip(EditorProvider editor, bool isDark) {
    return Container(
      height: 90,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF16191E) : const Color(0xFFF8FAFC),
        border: Border(
          top: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.border),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: editor.pages.length,
              itemBuilder: (context, index) {
                final isCurrent = editor.currentPageIndex == index;
                final page = editor.pages[index];

                return Container(
                  margin: const EdgeInsets.only(right: 12),
                  child: Stack(
                    children: [
                      GestureDetector(
                        onTap: () {
                          editor.setPageIndex(index);
                        },
                        child: Container(
                          width: 48,
                          height: 68,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: isCurrent
                                  ? (isDark ? AppColors.darkPrimary : AppColors.primary)
                                  : (isDark ? AppColors.darkBorder : AppColors.border),
                              width: isCurrent ? 2.5 : 1,
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              DocumentThumbnail(
                                pageCount: 1,
                                width: 44,
                                height: 64,
                                rotationDegrees: page.rotationDegrees,
                                filterType: page.filterType,
                                pageNumber: index + 1,
                                imagePath: page.processedImagePath ?? page.originalImagePath,
                              ),
                              Positioned(
                                bottom: 2,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.black87,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '${index + 1}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Delete button (if more than 1 page)
                      if (editor.pages.length > 1)
                        Positioned(
                          top: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: () => editor.deletePageAt(index),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: AppColors.error,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close_rounded, size: 10, color: Colors.white),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          // Add Page Button
          GestureDetector(
            onTap: _onAddPage,
            child: Container(
              width: 52,
              height: 68,
              decoration: BoxDecoration(
                border: Border.all(
                  color: isDark ? AppColors.darkBorder : AppColors.border,
                  style: BorderStyle.solid,
                ),
                borderRadius: BorderRadius.circular(6),
                color: isDark ? const Color(0xFF20262E) : Colors.white,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_rounded,
                    size: 22,
                    color: isDark ? AppColors.darkPrimary : AppColors.primary,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Add',
                    style: AppTypography.badge.copyWith(
                      color: isDark ? AppColors.darkPrimary : AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Bottom Toolbar: exactly 16 functional editing tools in strict specified order
  Widget _buildBottomToolbar(EditorProvider editor, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        border: Border(
          top: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.border),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: SingleChildScrollView(
            controller: _toolbarScrollController,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              children: [
                // 1. Crop
                _buildToolbarItem(
                  icon: Icons.crop_rounded,
                  label: 'Crop',
                  isActive: editor.activeTool == EditorActiveTool.crop,
                  isEnabled: true,
                  onTap: () => editor.setActiveTool(EditorActiveTool.crop),
                  isDark: isDark,
                ),
                // 2. Rotate
                _buildToolbarItem(
                  icon: Icons.rotate_right_rounded,
                  label: 'Rotate',
                  isActive: editor.activeTool == EditorActiveTool.rotate,
                  isEnabled: true,
                  onTap: () => editor.setActiveTool(EditorActiveTool.rotate),
                  isDark: isDark,
                ),
                // 3. Filter
                _buildToolbarItem(
                  icon: Icons.filter_b_and_w_rounded,
                  label: 'Filter',
                  isActive: editor.activeTool == EditorActiveTool.filter,
                  isEnabled: true,
                  onTap: () => editor.setActiveTool(EditorActiveTool.filter),
                  isDark: isDark,
                ),
                // 4. Adjust
                _buildToolbarItem(
                  icon: Icons.tune_rounded,
                  label: 'Adjust',
                  isActive: editor.activeTool == EditorActiveTool.adjust,
                  isEnabled: true,
                  onTap: () => editor.setActiveTool(EditorActiveTool.adjust),
                  isDark: isDark,
                ),
                // 5. Retake
                _buildToolbarItem(
                  icon: Icons.replay_rounded,
                  label: 'Retake',
                  isActive: false,
                  isEnabled: true,
                  onTap: () {
                    editor.startRetake(editor.currentPageIndex);
                    context.push(AppRouter.scanner);
                  },
                  isDark: isDark,
                ),
                // 6. Erase
                _buildToolbarItem(
                  icon: Icons.auto_fix_normal_rounded,
                  label: 'Erase',
                  isActive: editor.activeTool == EditorActiveTool.erase,
                  isEnabled: true,
                  onTap: () => editor.setActiveTool(EditorActiveTool.erase),
                  isDark: isDark,
                ),
                // 7. Annotate
                _buildToolbarItem(
                  icon: Icons.edit_note_rounded,
                  label: 'Annotate',
                  isActive: editor.activeTool == EditorActiveTool.annotate,
                  isEnabled: true,
                  onTap: () => editor.setActiveTool(EditorActiveTool.annotate),
                  isDark: isDark,
                ),
                // 8. Watermark
                _buildToolbarItem(
                  icon: Icons.branding_watermark_outlined,
                  label: 'Watermark',
                  isActive: editor.activeTool == EditorActiveTool.watermark,
                  isEnabled: true,
                  onTap: () => editor.setActiveTool(EditorActiveTool.watermark),
                  isDark: isDark,
                ),
                // 9. Redact
                _buildToolbarItem(
                  icon: Icons.security_rounded,
                  label: 'Redact',
                  isActive: editor.activeTool == EditorActiveTool.redact,
                  isEnabled: true,
                  onTap: () => editor.setActiveTool(EditorActiveTool.redact),
                  isDark: isDark,
                ),
                // 10. Resize
                _buildToolbarItem(
                  icon: Icons.aspect_ratio_rounded,
                  label: 'Resize',
                  isActive: editor.activeTool == EditorActiveTool.resize,
                  isEnabled: true,
                  onTap: () => editor.setActiveTool(EditorActiveTool.resize),
                  isDark: isDark,
                ),
                // 11. Margins
                _buildToolbarItem(
                  icon: Icons.crop_square_rounded,
                  label: 'Margins',
                  isActive: editor.activeTool == EditorActiveTool.margins,
                  isEnabled: true,
                  onTap: () => editor.setActiveTool(EditorActiveTool.margins),
                  isDark: isDark,
                ),
                // 12. Border
                _buildToolbarItem(
                  icon: Icons.border_outer_rounded,
                  label: 'Border',
                  isActive: editor.activeTool == EditorActiveTool.border,
                  isEnabled: true,
                  onTap: () => editor.setActiveTool(EditorActiveTool.border),
                  isDark: isDark,
                ),
                // 13. Reorder
                _buildToolbarItem(
                  icon: Icons.swap_horiz_rounded,
                  label: 'Reorder',
                  isActive: editor.activeTool == EditorActiveTool.reorder,
                  isEnabled: true,
                  onTap: () => editor.setActiveTool(EditorActiveTool.reorder),
                  isDark: isDark,
                ),
                // 14. Undo
                _buildToolbarItem(
                  icon: Icons.undo_rounded,
                  label: 'Undo',
                  isActive: false,
                  isEnabled: editor.canUndo,
                  onTap: editor.canUndo ? editor.undo : () {},
                  isDark: isDark,
                ),
                // 15. Redo
                _buildToolbarItem(
                  icon: Icons.redo_rounded,
                  label: 'Redo',
                  isActive: false,
                  isEnabled: editor.canRedo,
                  onTap: editor.canRedo ? editor.redo : () {},
                  isDark: isDark,
                ),
                // 16. Reset
                _buildToolbarItem(
                  icon: Icons.restart_alt_rounded,
                  label: 'Reset',
                  isActive: false,
                  isEnabled: true,
                  onTap: () => _confirmResetCurrentPage(editor),
                  isDark: isDark,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolbarItem({
    required IconData icon,
    required String label,
    required bool isActive,
    required bool isEnabled,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    final activeColor = isDark ? AppColors.darkPrimary : AppColors.primary;
    final inactiveColor = isDark ? AppColors.darkText : AppColors.textPrimary;
    final disabledColor = (isDark ? Colors.white : Colors.black).withAlpha(60);

    final color = !isEnabled
        ? disabledColor
        : (isActive ? activeColor : inactiveColor);

    return InkWell(
      onTap: isEnabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: isActive
              ? (isDark ? AppColors.darkPrimary.withAlpha(35) : AppColors.primary.withAlpha(20))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? activeColor.withAlpha(100) : Colors.transparent,
            width: 1.0,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 3),
            Text(
              label,
              style: AppTypography.badge.copyWith(
                color: color,
                fontWeight: isActive ? FontWeight.w700 : (isEnabled ? FontWeight.w500 : FontWeight.w400),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmResetCurrentPage(EditorProvider editor) async {
    final pageNum = editor.currentPageIndex + 1;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reset Page $pageNum?'),
        content: const Text(
          'This will revert all crop, rotation, filters, adjustments, annotations, erase marks, watermark, redactions, size, margins, and borders on this page back to the original scan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset Page'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      editor.resetCurrentPage();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Page $pageNum reset to original'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _showAddTextDialog(EditorProvider editor) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Text Annotation'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Text',
            hintText: 'Enter annotation text...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Add')),
        ],
      ),
    );
    if (text != null && text.isNotEmpty) {
      editor.addAnnotation(
        AnnotationElement(
          id: 'ann_${DateTime.now().microsecondsSinceEpoch}',
          type: AnnotationType.text,
          points: const [Offset(0.2, 0.4)],
          text: text,
          colorValue: _activeAnnotationColor.toARGB32(),
          fontSize: 20.0,
        ),
      );
    }
  }

  Future<void> _showAddSignatureDialog(EditorProvider editor) async {
    final sigPoints = await showDialog<List<Offset>>(
      context: context,
      builder: (ctx) => const _SignatureDrawDialog(),
    );
    if (sigPoints != null && sigPoints.isNotEmpty) {
      editor.addAnnotation(
        AnnotationElement(
          id: 'sig_${DateTime.now().microsecondsSinceEpoch}',
          type: AnnotationType.pen,
          points: sigPoints,
          colorValue: Colors.black.toARGB32(),
          strokeWidth: 3.5,
        ),
      );
    }
  }
}

class _SignatureDrawDialog extends StatefulWidget {
  const _SignatureDrawDialog();

  @override
  State<_SignatureDrawDialog> createState() => _SignatureDrawDialogState();
}

class _SignatureDrawDialogState extends State<_SignatureDrawDialog> {
  final List<Offset> _points = [];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Draw Signature'),
      content: SizedBox(
        width: 280,
        height: 180,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade400),
            borderRadius: BorderRadius.circular(8),
          ),
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                _points.add(details.localPosition);
              });
            },
            child: CustomPaint(
              painter: _SigPainter(_points),
              size: const Size(280, 180),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(() => _points.clear()),
          child: const Text('Clear'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _points.isEmpty
              ? null
              : () {
                  final norm = _points
                      .map((p) => Offset((p.dx / 280.0) * 0.4 + 0.3, (p.dy / 180.0) * 0.2 + 0.7))
                      .toList();
                  Navigator.pop(context, norm);
                },
          child: const Text('Insert'),
        ),
      ],
    );
  }
}

class _SigPainter extends CustomPainter {
  final List<Offset> points;
  _SigPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 3.0;

    for (int i = 0; i < points.length - 1; i++) {
      if ((points[i] - points[i + 1]).distance < 30) {
        canvas.drawLine(points[i], points[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _ExportSelection {
  final PdfExportQuality quality;
  final bool saveAsCopy;
  const _ExportSelection({required this.quality, this.saveAsCopy = false});
}

/// Modal Sheet for selecting PDF Export Quality (Small, Standard, High)
class _ExportQualitySheet extends StatefulWidget {
  final PdfExportQuality initialQuality;
  final bool isEditingExisting;

  const _ExportQualitySheet({
    required this.initialQuality,
    this.isEditingExisting = false,
  });

  @override
  State<_ExportQualitySheet> createState() => _ExportQualitySheetState();
}

class _ExportQualitySheetState extends State<_ExportQualitySheet> {
  late PdfExportQuality _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialQuality;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.isEditingExisting ? 'Save Document Changes' : 'PDF Export Quality',
              style: AppTypography.sectionTitle.copyWith(
                color: isDark ? AppColors.darkText : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Select file size and target resolution preset',
              style: AppTypography.bodySmall.copyWith(
                color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            _buildOption(
              quality: PdfExportQuality.standard,
              title: 'Standard (~200 DPI) - Recommended',
              subtitle: 'Balanced file size and sharp text for archival',
              isDark: isDark,
            ),
            _buildOption(
              quality: PdfExportQuality.small,
              title: 'Small (~150 DPI) - Compact',
              subtitle: 'Smallest file size, ideal for fast email & messaging',
              isDark: isDark,
            ),
            _buildOption(
              quality: PdfExportQuality.high,
              title: 'High (~300 DPI) - Maximum Clarity',
              subtitle: 'Full source resolution, best for printing',
              isDark: isDark,
            ),
            const SizedBox(height: 16),
            if (widget.isEditingExisting) ...[
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: isDark ? AppColors.darkPrimary : AppColors.primary,
                    foregroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
                  ),
                  onPressed: () => Navigator.pop(
                    context,
                    _ExportSelection(quality: _selected, saveAsCopy: false),
                  ),
                  child: const Text('Update Existing Document', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(
                    context,
                    _ExportSelection(quality: _selected, saveAsCopy: true),
                  ),
                  child: const Text('Save as New Copy'),
                ),
              ),
            ] else ...[
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: isDark ? AppColors.darkPrimary : AppColors.primary,
                    foregroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
                  ),
                  onPressed: () => Navigator.pop(
                    context,
                    _ExportSelection(quality: _selected, saveAsCopy: false),
                  ),
                  child: const Text('Export Document', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOption({
    required PdfExportQuality quality,
    required String title,
    required String subtitle,
    required bool isDark,
  }) {
    final isSelected = _selected == quality;
    return InkWell(
      onTap: () => setState(() => _selected = quality),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? (isDark ? AppColors.darkPrimary : AppColors.primary)
                : (isDark ? AppColors.darkBorder : AppColors.border),
            width: isSelected ? 2 : 1,
          ),
          color: isSelected
              ? (isDark ? AppColors.darkPrimary.withAlpha(25) : AppColors.primary.withAlpha(15))
              : Colors.transparent,
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected
                  ? (isDark ? AppColors.darkPrimary : AppColors.primary)
                  : (isDark ? AppColors.darkTextSecondary : AppColors.textSecondary),
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isDark ? AppColors.darkText : AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Interactive draggable 4 corners AND 4 edge handles overlay for scan crop editing.
class _InteractiveCornerOverlay extends StatelessWidget {
  final List<Offset> corners;
  final bool isCropActive;
  final void Function(int index, Offset newNormalizedPos) onCornerMoved;
  final void Function(int edgeIndex, Offset deltaNormalized)? onEdgeMoved;

  const _InteractiveCornerOverlay({
    required this.corners,
    required this.isCropActive,
    required this.onCornerMoved,
    this.onEdgeMoved,
  });

  @override
  Widget build(BuildContext context) {
    if (corners.length < 4) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        // 4 edge midpoints
        final midpoints = [
          Offset((corners[0].dx + corners[1].dx) / 2, (corners[0].dy + corners[1].dy) / 2), // Top (0)
          Offset((corners[1].dx + corners[2].dx) / 2, (corners[1].dy + corners[2].dy) / 2), // Right (1)
          Offset((corners[2].dx + corners[3].dx) / 2, (corners[2].dy + corners[3].dy) / 2), // Bottom (2)
          Offset((corners[3].dx + corners[0].dx) / 2, (corners[3].dy + corners[0].dy) / 2), // Left (3)
        ];

        return Stack(
          children: [
            // Outlines connecting the 4 corners + grid
            CustomPaint(
              size: Size(w, h),
              painter: _EditorOutlinePainter(corners: corners, isCropActive: isCropActive),
            ),

            // 4 draggable edge handles (midpoints)
            for (int e = 0; e < 4; e++)
              Positioned(
                left: (midpoints[e].dx * w) - 15,
                top: (midpoints[e].dy * h) - 15,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    onEdgeMoved?.call(e, Offset(details.delta.dx / w, details.delta.dy / h));
                  },
                  child: Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(70),
                            blurRadius: 3,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.drag_handle_rounded, size: 10, color: Colors.white),
                    ),
                  ),
                ),
              ),

            // 4 draggable corner handles
            for (int i = 0; i < 4; i++)
              Positioned(
                left: (corners[i].dx * w) - 20,
                top: (corners[i].dy * h) - 20,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    final newX = (corners[i].dx * w + details.delta.dx) / w;
                    final newY = (corners[i].dy * h + details.delta.dy) / h;
                    onCornerMoved(i, Offset(newX, newY));
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.primary, width: 3.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(50),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _EditorOutlinePainter extends CustomPainter {
  final List<Offset> corners;
  final bool isCropActive;

  _EditorOutlinePainter({required this.corners, required this.isCropActive});

  @override
  void paint(Canvas canvas, Size size) {
    final actual = corners.map((c) => Offset(c.dx * size.width, c.dy * size.height)).toList();

    final path = Path()
      ..moveTo(actual[0].dx, actual[0].dy)
      ..lineTo(actual[1].dx, actual[1].dy)
      ..lineTo(actual[2].dx, actual[2].dy)
      ..lineTo(actual[3].dx, actual[3].dy)
      ..close();

    final fillPaint = Paint()
      ..color = AppColors.primary.withAlpha(15)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    final paint = Paint()
      ..color = AppColors.primary.withAlpha(isCropActive ? 230 : 120)
      ..strokeWidth = isCropActive ? 2.5 : 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawPath(path, paint);

    // Subtle 3x3 grid inside crop boundary
    if (isCropActive) {
      final gridPaint = Paint()
        ..color = Colors.white.withAlpha(60)
        ..strokeWidth = 1.0;

      for (double t = 1 / 3; t < 1.0; t += 1 / 3) {
        // Vertical grid lines
        final topPt = Offset.lerp(actual[0], actual[1], t)!;
        final botPt = Offset.lerp(actual[3], actual[2], t)!;
        canvas.drawLine(topPt, botPt, gridPaint);

        // Horizontal grid lines
        final leftPt = Offset.lerp(actual[0], actual[3], t)!;
        final rightPt = Offset.lerp(actual[1], actual[2], t)!;
        canvas.drawLine(leftPt, rightPt, gridPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _EditorOutlinePainter oldDelegate) => true;
}
