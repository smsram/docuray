import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../constants/app_dimensions.dart';
import '../providers/documents_provider.dart';
import '../../models/models.dart';
import 'app_card.dart';
import 'confirm_dialog.dart';
import 'document_thumbnail.dart';

/// Reusable DocumentCard supporting both Grid and List layouts.
class DocumentCard extends StatelessWidget {
  final Document document;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isGrid;
  final bool isSelectionMode;
  final bool isSelected;
  final ValueChanged<bool?>? onSelectChanged;

  const DocumentCard({
    super.key,
    required this.document,
    this.onTap,
    this.onLongPress,
    this.isGrid = false,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onSelectChanged,
  });

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final difference = now.difference(dt);

    if (difference.inDays == 0 && now.day == dt.day) {
      return 'Today';
    } else if (difference.inDays <= 1 && now.day - dt.day == 1) {
      return 'Yesterday';
    } else {
      return DateFormat('MMM d').format(dt);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (isGrid) {
      return _buildGridCard(context, isDark);
    }
    return _buildListCard(context, isDark);
  }

  Widget _buildGridCard(BuildContext context, bool isDark) {
    return AppCard(
      onTap: onTap,
      onLongPress: onLongPress,
      isSelected: isSelected,
      padding: const EdgeInsets.all(AppDimensions.space12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thumbnail area
          Expanded(
            child: Stack(
              children: [
                Center(
                  child: DocumentThumbnail(
                    pageCount: document.pageCount,
                    width: 90,
                    height: 120,
                    documentTitle: document.title,
                    imagePath: document.thumbnailPath ?? (document.pages.isNotEmpty ? (document.pages.first.thumbnailPath ?? document.pages.first.processedImagePath) : null),
                  ),
                ),
                // Top-right status pills
                Positioned(
                  top: 0,
                  right: 0,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (document.isFavorite) ...[
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.darkSurface : Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(20),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.star_rounded,
                            size: 14,
                            color: AppColors.favoriteYellow,
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      if (document.syncMetadata.status == SyncStatus.synced)
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.darkSurface : Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(20),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.cloud_done_rounded,
                            size: 14,
                            color: AppColors.syncedGreen,
                          ),
                        ),
                    ],
                  ),
                ),
                // Selection checkbox overlay
                if (isSelectionMode)
                  Positioned(
                    top: 0,
                    left: 0,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? (isDark ? AppColors.darkPrimary : AppColors.primary)
                            : (isDark ? AppColors.darkSurface : Colors.white),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? Colors.transparent
                              : (isDark ? AppColors.darkBorder : AppColors.border),
                          width: 1.5,
                        ),
                      ),
                      child: isSelected
                          ? Icon(
                              Icons.check_rounded,
                              size: 16,
                              color: isDark ? const Color(0xFF0F172A) : Colors.white,
                            )
                          : null,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppDimensions.space8),
          // Title
          Text(
            document.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyMedium.copyWith(
              color: isDark ? AppColors.darkText : AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          // Meta (Page count & date)
          Text(
            '${document.pageCount} ${document.pageCount == 1 ? 'page' : 'pages'} · ${_formatDate(document.createdAt)}',
            style: AppTypography.secondary.copyWith(
              color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildListCard(BuildContext context, bool isDark) {
    return AppCard(
      onTap: onTap,
      onLongPress: onLongPress,
      isSelected: isSelected,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          // Selection checkbox in selection mode
          if (isSelectionMode) ...[
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: isSelected
                    ? (isDark ? AppColors.darkPrimary : AppColors.primary)
                    : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? Colors.transparent
                      : (isDark ? AppColors.darkBorder : AppColors.border),
                  width: 1.5,
                ),
              ),
              child: isSelected
                  ? Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: isDark ? const Color(0xFF0F172A) : Colors.white,
                    )
                  : null,
            ),
            const SizedBox(width: AppDimensions.space12),
          ],
          // Smaller thumbnail
          DocumentThumbnail(
            pageCount: document.pageCount,
            width: 44,
            height: 58,
            documentTitle: document.title,
            imagePath: document.thumbnailPath ?? (document.pages.isNotEmpty ? (document.pages.first.thumbnailPath ?? document.pages.first.processedImagePath) : null),
          ),
          const SizedBox(width: AppDimensions.space16),
          // Title and metadata
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  document.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyMedium.copyWith(
                    color: isDark ? AppColors.darkText : AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '${document.pageCount} ${document.pageCount == 1 ? 'page' : 'pages'} · ${_formatDate(document.createdAt)}',
                      style: AppTypography.secondary.copyWith(
                        color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (document.isFavorite)
                      const Icon(
                        Icons.star_rounded,
                        size: 14,
                        color: AppColors.favoriteYellow,
                      ),
                  ],
                ),
              ],
            ),
          ),
          // Status indicators & Overflow Menu
          if (!isSelectionMode) ...[
            if (document.syncMetadata.status == SyncStatus.synced)
              const Icon(
                Icons.cloud_done_rounded,
                size: 18,
                color: AppColors.syncedGreen,
              )
            else if (document.syncMetadata.status == SyncStatus.syncing)
              const Icon(
                Icons.sync_rounded,
                size: 18,
                color: AppColors.primary,
              ),
            const SizedBox(width: 2),
            PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert_rounded,
                size: 20,
                color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'Options',
              onSelected: (val) => _handleMenuAction(context, val),
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'rename',
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined, size: 18),
                      SizedBox(width: 10),
                      Text('Rename'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'share',
                  child: Row(
                    children: [
                      Icon(Icons.share_outlined, size: 18),
                      SizedBox(width: 10),
                      Text('Share'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'move',
                  child: Row(
                    children: [
                      Icon(Icons.drive_file_move_outlined, size: 18),
                      SizedBox(width: 10),
                      Text('Move to Folder'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'favorite',
                  child: Row(
                    children: [
                      Icon(
                        document.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                        size: 18,
                        color: document.isFavorite ? AppColors.favoriteYellow : null,
                      ),
                      const SizedBox(width: 10),
                      Text(document.isFavorite ? 'Remove Favorite' : 'Add to Favorites'),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.error),
                      SizedBox(width: 10),
                      Text('Delete', style: TextStyle(color: AppColors.error)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _handleMenuAction(BuildContext context, String action) {
    final provider = context.read<DocumentsProvider>();
    switch (action) {
      case 'rename':
        _showRenameDialog(context, provider);
        break;
      case 'share':
        _shareDocument(context);
        break;
      case 'move':
        _showMoveToFolderSheet(context, provider);
        break;
      case 'favorite':
        provider.toggleFavorite(document.id);
        break;
      case 'delete':
        _deleteDocument(context, provider);
        break;
    }
  }

  void _showRenameDialog(BuildContext context, DocumentsProvider provider) {
    final controller = TextEditingController(text: document.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Document'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Document title'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final newTitle = controller.text.trim();
              if (newTitle.isNotEmpty && newTitle != document.title) {
                provider.renameDocument(document.id, newTitle);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _shareDocument(BuildContext context) async {
    if (document.pdfPath != null) {
      final f = File(document.pdfPath!);
      if (await f.exists()) {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(f.path, name: '${document.title}.pdf', mimeType: 'application/pdf')],
            text: document.title,
          ),
        );
        return;
      }
    }
    // Fallback to images
    final imageFiles = <XFile>[];
    for (final p in document.pages) {
      final path = p.processedImagePath ?? p.originalImagePath;
      if (path != null && await File(path).exists()) {
        imageFiles.add(XFile(path, mimeType: 'image/jpeg'));
      }
    }
    if (imageFiles.isNotEmpty) {
      await SharePlus.instance.share(
        ShareParams(files: imageFiles, text: document.title),
      );
    }
  }

  void _showMoveToFolderSheet(BuildContext context, DocumentsProvider provider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: AppDimensions.borderSheet),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  'Move to Folder',
                  style: AppTypography.subsectionTitle.copyWith(
                    color: isDark ? AppColors.darkText : AppColors.textPrimary,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.home_outlined),
                title: const Text('None (Root Library)'),
                trailing: document.folderId == null
                    ? const Icon(Icons.check_rounded, color: AppColors.primary)
                    : null,
                onTap: () {
                  provider.moveDocument(document.id, null);
                  Navigator.pop(ctx);
                },
              ),
              ...provider.folders.map((f) {
                return ListTile(
                  leading: Icon(f.icon, color: f.color),
                  title: Text(f.name),
                  trailing: document.folderId == f.id
                      ? const Icon(Icons.check_rounded, color: AppColors.primary)
                      : null,
                  onTap: () {
                    provider.moveDocument(document.id, f.id);
                    Navigator.pop(ctx);
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteDocument(BuildContext context, DocumentsProvider provider) async {
    final confirm = await ConfirmDialog.show(
      context,
      title: 'Delete "${document.title}"?',
      message: 'This document and its scanned pages will be permanently deleted.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (confirm == true) {
      await provider.deleteDocument(document.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted "${document.title}".')),
        );
      }
    }
  }
}
