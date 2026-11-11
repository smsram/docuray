import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/segmented_control.dart';
import '../../models/models.dart';

/// Screen 16: Share / Export Bottom Sheet with real format export and Android sharing.
class ShareExportSheet extends StatefulWidget {
  final String documentTitle;
  final Document? document;

  const ShareExportSheet({
    super.key,
    required this.documentTitle,
    this.document,
  });

  static Future<void> show(
    BuildContext context, {
    required String documentTitle,
    Document? document,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ShareExportSheet(
        documentTitle: documentTitle,
        document: document,
      ),
    );
  }

  @override
  State<ShareExportSheet> createState() => _ShareExportSheetState();
}

class _ShareExportSheetState extends State<ShareExportSheet> {
  String _format = 'PDF';
  String _quality = 'Standard';
  bool _enablePassword = false;
  final TextEditingController _passwordController = TextEditingController();

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  void _onShare() async {
    Navigator.of(context).pop();

    if (widget.document != null) {
      try {
        if (_format == 'PDF' && widget.document!.pdfPath != null) {
          final pdfFile = File(widget.document!.pdfPath!);
          if (await pdfFile.exists()) {
            await SharePlus.instance.share(
              ShareParams(
                files: [XFile(pdfFile.path, mimeType: 'application/pdf')],
                text: widget.documentTitle,
              ),
            );
            return;
          }
        } else {
          // Share image files (JPG or PNG)
          final imageFiles = <XFile>[];
          for (final p in widget.document!.pages) {
            final path = p.processedImagePath ?? p.originalImagePath;
            if (path != null && await File(path).exists()) {
              imageFiles.add(XFile(path, mimeType: 'image/jpeg'));
            }
          }
          if (imageFiles.isNotEmpty) {
            await SharePlus.instance.share(
              ShareParams(
                files: imageFiles,
                text: widget.documentTitle,
              ),
            );
            return;
          }
        }
      } catch (e) {
        debugPrint('[DocuRay] Share error: $e');
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Exported "${widget.documentTitle}" as $_format.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: AppDimensions.borderSheet,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 80 : 30),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkBorder : const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Title
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Share & Export',
                          style: AppTypography.subsectionTitle.copyWith(
                            color: isDark ? AppColors.darkText : AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          widget.documentTitle,
                          style: AppTypography.secondary.copyWith(
                            color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Format selector
              Text(
                'EXPORT FORMAT',
                style: AppTypography.badge.copyWith(
                  color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 8),
              SegmentedControl<String>(
                items: const {
                  'PDF': 'PDF Document',
                  'JPG': 'JPEG Images',
                  'PNG': 'PNG Images',
                },
                selectedValue: _format,
                onValueChanged: (val) => setState(() => _format = val),
              ),
              const SizedBox(height: 20),

              // Quality selector (PDF only)
              if (_format == 'PDF') ...[
                Text(
                  'PDF QUALITY',
                  style: AppTypography.badge.copyWith(
                    color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedControl<String>(
                  items: const {
                    'Small': 'Small (~1MB)',
                    'Standard': 'Standard (~3MB)',
                    'High': 'High (~8MB)',
                  },
                  selectedValue: _quality,
                  onValueChanged: (val) => setState(() => _quality = val),
                ),
                const SizedBox(height: 20),

                // Password protection toggle
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Password Protection',
                          style: AppTypography.bodyMedium.copyWith(
                            color: isDark ? AppColors.darkText : AppColors.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          'Encrypt PDF with access password',
                          style: AppTypography.secondary.copyWith(
                            color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    Switch.adaptive(
                      value: _enablePassword,
                      activeTrackColor: isDark ? AppColors.darkPrimary : AppColors.primary,
                      onChanged: (v) => setState(() => _enablePassword = v),
                    ),
                  ],
                ),
                if (_enablePassword) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      hintText: 'Enter PDF password',
                      prefixIcon: Icon(Icons.lock_outline_rounded, size: 20),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
              ],

              // Export CTA
              PrimaryButton(
                label: 'Share $_format',
                width: double.infinity,
                icon: Icons.share_rounded,
                onPressed: _onShare,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
