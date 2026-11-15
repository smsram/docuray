import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/providers/documents_provider.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_buttons.dart';

/// Screen 14: Real Storage Screen calculating filesystem storage metrics and cache clearing.
class StorageScreen extends StatefulWidget {
  const StorageScreen({super.key});

  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  int _documentBytes = 0;
  int _cacheBytes = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _calculateStorage();
  }

  bool _isSafeToClear(FileSystemEntity entity) {
    final path = entity.path.toLowerCase();
    final name = entity.uri.pathSegments.isNotEmpty
        ? entity.uri.pathSegments.last.toLowerCase()
        : '';

    // NEVER touch any Google, Play Services, OAuth, Auth, or system-related cache
    if (path.contains('google') ||
        path.contains('gms') ||
        path.contains('auth') ||
        path.contains('signin') ||
        path.contains('oauth') ||
        path.contains('credential') ||
        path.contains('play-services') ||
        path.contains('webview') ||
        path.contains('code_cache')) {
      return false;
    }

    // Explicitly safe DocuRay temporary image and cache files
    if (name.startsWith('cap_') ||
        name.startsWith('raw_') ||
        name.startsWith('cropped_') ||
        name.startsWith('proc_') ||
        name.startsWith('preview_') ||
        name.startsWith('temp_') ||
        name.startsWith('docuray_') ||
        name.startsWith('ai_upload_') ||
        name.startsWith('crop_') ||
        name.startsWith('scan_') ||
        name.startsWith('filter_') ||
        name.startsWith('bundle_') ||
        name.startsWith('export_') ||
        name.startsWith('temp_download_') ||
        name.endsWith('.tmp') ||
        name.endsWith('.temp') ||
        name.endsWith('.part')) {
      return true;
    }

    // Safe temporary directories
    if (entity is Directory) {
      if (name.contains('image_picker') ||
          name.contains('docuray') ||
          name.startsWith('temp_')) {
        return true;
      }
    }

    return false;
  }

  Future<void> _calculateStorage() async {
    setState(() => _isLoading = true);
    int docTotal = 0;
    int cacheTotal = 0;

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final docDir = Directory('${appDir.path}/documents');
      if (await docDir.exists()) {
        await for (final entity in docDir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            try {
              docTotal += await entity.length();
            } catch (_) {}
          }
        }
      }

      final tempDir = await getTemporaryDirectory();
      if (await tempDir.exists()) {
        await for (final entity in tempDir.list(recursive: true, followLinks: false)) {
          if (_isSafeToClear(entity) && entity is File) {
            try {
              cacheTotal += await entity.length();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _documentBytes = docTotal;
        _cacheBytes = cacheTotal;
        _isLoading = false;
      });
    }
  }

  Future<void> _confirmAndClearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? AppColors.darkSurface : AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Clear Temporary Cache',
            style: AppTypography.subsectionTitle.copyWith(
              color: isDark ? AppColors.darkText : AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This will remove temporary scratch files, image processing cache, and camera previews to free up storage.',
                style: AppTypography.body.copyWith(
                  color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (isDark ? AppColors.darkPrimary : AppColors.primary).withAlpha(15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: (isDark ? AppColors.darkPrimary : AppColors.primary).withAlpha(40),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.check_circle_outline_rounded, size: 16, color: AppColors.success),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Saved documents and folders are preserved',
                            style: AppTypography.caption.copyWith(
                              color: isDark ? AppColors.darkText : AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.check_circle_outline_rounded, size: 16, color: AppColors.success),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Google account login & Drive backup stay connected',
                            style: AppTypography.caption.copyWith(
                              color: isDark ? AppColors.darkText : AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                ),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
              child: const Text('Clear Cache'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _clearCache();
    }
  }

  Future<void> _clearCache() async {
    int cleared = 0;
    try {
      final tempDir = await getTemporaryDirectory();
      if (await tempDir.exists()) {
        await for (final entity in tempDir.list(recursive: false)) {
          if (!_isSafeToClear(entity)) continue;
          try {
            if (entity is File) {
              cleared += await entity.length();
              await entity.delete();
            } else if (entity is Directory) {
              cleared += await _getDirectorySize(entity);
              await entity.delete(recursive: true);
            }
          } catch (_) {}
        }
      }
    } catch (_) {}

    await _calculateStorage();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Temporary cache cleared (${_formatBytes(cleared)} freed). Documents and Google account connection preserved.',
          ),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<int> _getDirectorySize(Directory dir) async {
    int size = 0;
    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            size += await entity.length();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return size;
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final docsProvider = context.watch<DocumentsProvider>();
    final docs = docsProvider.documents;
    final totalUsed = _documentBytes + _cacheBytes;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Storage & Data'),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: AppDimensions.screenPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Storage Overview Card
                    AppCard(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Internal App Storage',
                            style: AppTypography.subsectionTitle.copyWith(
                              color: isDark ? AppColors.darkText : AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                _formatBytes(totalUsed),
                                style: AppTypography.largeTitle.copyWith(
                                  color: isDark ? AppColors.darkPrimary : AppColors.primary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'used by DocuRay',
                                style: AppTypography.body.copyWith(
                                  color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: totalUsed > 0 ? (totalUsed / (100 * 1024 * 1024)).clamp(0.05, 1.0) : 0.0,
                              minHeight: 8,
                              backgroundColor: isDark ? AppColors.darkBorder : const Color(0xFFE2E8F0),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                isDark ? AppColors.darkPrimary : AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Breakdown Section
                    Text(
                      'STORAGE BREAKDOWN',
                      style: AppTypography.badge.copyWith(
                        color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 10),
                    AppCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _buildBreakdownRow(
                            icon: Icons.description_outlined,
                            label: 'Documents & PDFs (${docs.length})',
                            size: _formatBytes(_documentBytes),
                            color: AppColors.primary,
                            isDark: isDark,
                          ),
                          const Divider(),
                          _buildBreakdownRow(
                            icon: Icons.image_outlined,
                            label: 'Temporary Cache & Processing',
                            size: _formatBytes(_cacheBytes),
                            color: AppColors.warning,
                            isDark: isDark,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Clean Cache CTA
                    SecondaryButton(
                      label: 'Clear Temporary Cache',
                      icon: Icons.cleaning_services_rounded,
                      width: double.infinity,
                      onPressed: _confirmAndClearCache,
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildBreakdownRow({
    required IconData icon,
    required String label,
    required String size,
    required Color color,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: AppTypography.bodyMedium.copyWith(
                color: isDark ? AppColors.darkText : AppColors.textPrimary,
              ),
            ),
          ),
          Text(
            size,
            style: AppTypography.bodyMedium.copyWith(
              color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
