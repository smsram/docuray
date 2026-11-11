import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/routing/app_router.dart';
import '../../core/providers/scanner_provider.dart';
import '../../core/providers/editor_provider.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/app_card.dart';

enum ImportSource { gallery, files }
enum ImportType { singleImage, multipleImages, pdf }

/// Screen 4: Import screen supporting Gallery/Files, Single/Multiple Images, and PDF imports.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  ImportSource _source = ImportSource.gallery;
  ImportType _type = ImportType.multipleImages;

  final List<String> _sampleSelectedFiles = [
    'IMG_20260925_001.jpg',
    'IMG_20260925_002.jpg',
    'IMG_20260925_003.jpg',
  ];

  void _onConfirmImport() async {
    final scanner = context.read<ScannerProvider>();
    final pages = await scanner.importFromGallery();
    if (pages.isNotEmpty && mounted) {
      final editor = context.read<EditorProvider>();
      editor.initializeWithPages(pages);
      context.push(AppRouter.editor);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      appBar: AppBar(
        title: const Text('Import Documents'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: AppDimensions.screenPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Source Selector (Gallery vs Files)
                    Text(
                      'Source',
                      style: AppTypography.subsectionTitle.copyWith(
                        color: isDark ? AppColors.darkText : AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildSourceCard(
                            source: ImportSource.gallery,
                            title: 'Gallery',
                            subtitle: 'Photos & scans',
                            icon: Icons.photo_library_outlined,
                            isDark: isDark,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildSourceCard(
                            source: ImportSource.files,
                            title: 'Files',
                            subtitle: 'PDFs & storage',
                            icon: Icons.folder_open_outlined,
                            isDark: isDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Type Options
                    Text(
                      'Import Type',
                      style: AppTypography.subsectionTitle.copyWith(
                        color: isDark ? AppColors.darkText : AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    AppCard(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        children: [
                          _buildTypeTile(
                            title: 'Multiple Images (Batch)',
                            subtitle: 'Convert multiple photos into a multi-page document',
                            isSelected: _type == ImportType.multipleImages,
                            onTap: () => setState(() => _type = ImportType.multipleImages),
                            isDark: isDark,
                          ),
                          const Divider(),
                          _buildTypeTile(
                            title: 'Single Image',
                            subtitle: 'Import a single photo or receipt',
                            isSelected: _type == ImportType.singleImage,
                            onTap: () => setState(() => _type = ImportType.singleImage),
                            isDark: isDark,
                          ),
                          const Divider(),
                          _buildTypeTile(
                            title: 'PDF Document',
                            subtitle: 'Import and enhance an existing PDF file',
                            isSelected: _type == ImportType.pdf,
                            onTap: () => setState(() => _type = ImportType.pdf),
                            isDark: isDark,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Selected Items Preview
                    Text(
                      'Selected for Import (${_sampleSelectedFiles.length})',
                      style: AppTypography.subsectionTitle.copyWith(
                        color: isDark ? AppColors.darkText : AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    AppCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          for (int i = 0; i < _sampleSelectedFiles.length; i++) ...[
                            Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF262C34) : const Color(0xFFFAFBFD),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
                                  ),
                                  child: Icon(
                                    _type == ImportType.pdf ? Icons.picture_as_pdf_rounded : Icons.image_rounded,
                                    size: 20,
                                    color: isDark ? AppColors.darkPrimary : AppColors.primary,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _sampleSelectedFiles[i],
                                        style: AppTypography.bodyMedium.copyWith(
                                          color: isDark ? AppColors.darkText : AppColors.textPrimary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Page ${i + 1} · 2.4 MB · High Quality',
                                        style: AppTypography.secondary.copyWith(
                                          color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
                                  color: AppColors.error,
                                  onPressed: () {
                                    setState(() {
                                      _sampleSelectedFiles.removeAt(i);
                                    });
                                  },
                                ),
                              ],
                            ),
                            if (i < _sampleSelectedFiles.length - 1) const Divider(height: 20),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Import CTA
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: PrimaryButton(
                label: 'Import ${_sampleSelectedFiles.length} ${_sampleSelectedFiles.length == 1 ? 'Item' : 'Items'}',
                width: double.infinity,
                icon: Icons.file_download_done_rounded,
                onPressed: _sampleSelectedFiles.isNotEmpty ? _onConfirmImport : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceCard({
    required ImportSource source,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isDark,
  }) {
    final isSelected = _source == source;

    return AppCard(
      isSelected: isSelected,
      onTap: () => setState(() => _source = source),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 26,
            color: isSelected
                ? (isDark ? AppColors.darkPrimary : AppColors.primary)
                : (isDark ? AppColors.darkTextSecondary : AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: AppTypography.bodyMedium.copyWith(
              color: isDark ? AppColors.darkText : AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: AppTypography.secondary.copyWith(
              color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeTile({
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return ListTile(
      title: Text(
        title,
        style: AppTypography.bodyMedium.copyWith(
          color: isDark ? AppColors.darkText : AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: AppTypography.secondary.copyWith(
          color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
        ),
      ),
      trailing: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected
                ? (isDark ? AppColors.darkPrimary : AppColors.primary)
                : (isDark ? AppColors.darkBorder : AppColors.border),
            width: isSelected ? 6 : 1.5,
          ),
        ),
      ),
      onTap: onTap,
    );
  }
}

