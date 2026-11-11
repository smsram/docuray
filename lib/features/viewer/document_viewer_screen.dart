import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/providers/documents_provider.dart';
import '../../core/widgets/document_thumbnail.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/loading_state.dart';
import '../../core/widgets/app_buttons.dart';
import 'document_more_sheet.dart';
import '../share/share_export_sheet.dart';

/// Screen 7: Document Viewer Screen with pinch-to-zoom interactive viewer,
/// page navigation, real PDF/JPG sharing, editing, and options.
class DocumentViewerScreen extends StatefulWidget {
  final String documentId;

  const DocumentViewerScreen({super.key, required this.documentId});

  @override
  State<DocumentViewerScreen> createState() => _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends State<DocumentViewerScreen> {
  late PageController _pageController;
  int _currentPageIndex = 0;
  final bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final docsProvider = context.watch<DocumentsProvider>();
    final document = docsProvider.getDocument(widget.documentId);

    if (_isLoading) {
      return const Scaffold(
        body: LoadingState(message: 'Opening document...'),
      );
    }

    if (document == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => context.pop(),
          ),
          title: const Text('Document not found'),
        ),
        body: EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Document not found',
          description: 'This document may have been deleted or moved.',
          buttonLabel: 'Back to Home',
          onButtonPressed: () => context.go('/home'),
        ),
      );
    }

    final pages = document.pages;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
          tooltip: 'Back',
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              document.title,
              style: AppTypography.screenTitle.copyWith(
                fontSize: 18,
                color: isDark ? AppColors.darkText : AppColors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${document.pageCount} ${document.pageCount == 1 ? 'page' : 'pages'} · ${document.formattedSize}',
              style: AppTypography.caption.copyWith(
                color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              document.isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
              color: document.isFavorite ? AppColors.favoriteYellow : null,
            ),
            tooltip: 'Favorite',
            onPressed: () => docsProvider.toggleFavorite(document.id),
          ),
          IconButton(
            icon: const Icon(Icons.more_horiz_rounded),
            tooltip: 'More actions',
            onPressed: () {
              DocumentMoreSheet.show(
                context,
                document: document,
                provider: docsProvider,
                onDeleted: () => context.go('/home'),
                onRenamed: () => setState(() {}),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Large Document/PDF Preview Area with Pinch-to-Zoom
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: PageView.builder(
                controller: _pageController,
                itemCount: pages.length,
                onPageChanged: (index) => setState(() => _currentPageIndex = index),
                itemBuilder: (context, index) {
                  final p = pages[index];
                  final imagePath = p.processedImagePath ?? p.originalImagePath;

                  if (imagePath != null && File(imagePath).existsSync()) {
                    return InteractiveViewer(
                      minScale: 1.0,
                      maxScale: 4.5,
                      child: Center(
                        child: Container(
                          decoration: BoxDecoration(
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(isDark ? 60 : 25),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.file(
                              File(imagePath),
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  return Center(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return DocumentThumbnail(
                          pageCount: 1,
                          width: constraints.maxWidth * 0.90,
                          height: constraints.maxHeight * 0.94,
                          rotationDegrees: p.rotationDegrees,
                          filterType: p.filterType,
                          pageNumber: index + 1,
                          documentTitle: document.title,
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ),

          // 2. Page Indicator & Thumbnail Strip
          if (pages.length > 1) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Text(
                'Page ${_currentPageIndex + 1} of ${pages.length}',
                style: AppTypography.caption.copyWith(
                  color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(
              height: 64,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                itemCount: pages.length,
                itemBuilder: (context, index) {
                  final isSelected = index == _currentPageIndex;
                  final p = pages[index];
                  final thumb = p.thumbnailPath ?? p.processedImagePath ?? p.originalImagePath;

                  return GestureDetector(
                    onTap: () {
                      _pageController.animateToPage(
                        index,
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                      );
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 10),
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isSelected
                              ? (isDark ? AppColors.darkPrimary : AppColors.primary)
                              : Colors.transparent,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: DocumentThumbnail(
                        pageCount: 1,
                        width: 32,
                        height: 46,
                        pageNumber: index + 1,
                        filterType: p.filterType,
                        rotationDegrees: p.rotationDegrees,
                        imagePath: thumb,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],

          // 3. Bottom Actions: Share, Edit, and Future AI CTA
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : Colors.white,
              border: Border(
                top: BorderSide(
                  color: isDark ? AppColors.darkBorder : AppColors.border,
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  // Share Button
                  Expanded(
                    child: SecondaryButton(
                      label: 'Share',
                      icon: Icons.share_rounded,
                      height: 46,
                      onPressed: () {
                        ShareExportSheet.show(
                          context,
                          documentTitle: document.title,
                          document: document,
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Edit Button
                  Expanded(
                    child: SecondaryButton(
                      label: 'Edit',
                      icon: Icons.edit_note_rounded,
                      height: 46,
                      onPressed: () {
                        context.push(
                          '/editor',
                          extra: {'documentId': document.id},
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Future AI Action Button (Coming in Phase 2)
                  Expanded(
                    flex: 1,
                    child: AIActionButton(
                      label: 'Ask AI',
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('AI Assistant will be available in the upcoming AI update.'),
                            duration: Duration(seconds: 2),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
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
}
