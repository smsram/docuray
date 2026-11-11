import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../constants/app_dimensions.dart';
import '../../models/models.dart';
import 'app_card.dart';
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
          // Status indicators
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
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: isDark ? AppColors.darkTextSecondary.withAlpha(120) : AppColors.textSecondary.withAlpha(100),
            ),
          ],
        ],
      ),
    );
  }
}
