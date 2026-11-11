import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/providers/documents_provider.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_buttons.dart';

/// Screen 10: AI Quick Action Result with dedicated structured layouts for Summarize,
/// Explain simply, Extract info, Translate, Notes, and Questions.
class AiQuickActionScreen extends StatefulWidget {
  final String documentId;
  final String actionType;

  const AiQuickActionScreen({
    super.key,
    required this.documentId,
    required this.actionType,
  });

  @override
  State<AiQuickActionScreen> createState() => _AiQuickActionScreenState();
}

class _AiQuickActionScreenState extends State<AiQuickActionScreen> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  String _getTitle() {
    switch (widget.actionType) {
      case 'summarize':
        return 'Document Summary';
      case 'explain':
        return 'Simplified Explanation';
      case 'extract':
        return 'Extracted Data & Tables';
      case 'translate':
        return 'Translation Preview';
      case 'notes':
        return 'Key Study Notes';
      case 'questions':
        return 'Practice Questions';
      default:
        return 'AI Analysis';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final doc = context.watch<DocumentsProvider>().getDocument(widget.documentId);
    final docTitle = doc?.title ?? 'Document';
    final pageCount = doc?.pageCount ?? 1;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: Text(_getTitle()),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share result',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('AI result copied to clipboard.')),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? _buildSkeletonLoading(isDark)
            : SingleChildScrollView(
                padding: AppDimensions.screenPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Context pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : AppColors.aiBackground,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.auto_awesome_rounded,
                            size: 14,
                            color: isDark ? AppColors.darkPrimary : AppColors.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Generated from $docTitle · $pageCount ${pageCount == 1 ? 'page' : 'pages'}',
                            style: AppTypography.badge.copyWith(
                              color: isDark ? AppColors.darkPrimary : AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Preview watermark notice
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkBorder.withAlpha(80) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.textSecondary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Sample preview layout. Real AI model results will appear here in Phase 2.',
                              style: AppTypography.caption.copyWith(
                                color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Structured Content Layout
                    if (widget.actionType == 'summarize')
                      _buildSummaryContent(isDark)
                    else if (widget.actionType == 'explain')
                      _buildExplainContent(isDark)
                    else if (widget.actionType == 'extract')
                      _buildExtractContent(isDark)
                    else if (widget.actionType == 'notes')
                      _buildNotesContent(isDark)
                    else
                      _buildGenericContent(isDark),

                    const SizedBox(height: 28),

                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: SecondaryButton(
                            label: 'Copy Text',
                            icon: Icons.copy_rounded,
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Copied to clipboard.')),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: PrimaryButton(
                            label: 'Ask Follow-up',
                            icon: Icons.chat_bubble_outline_rounded,
                            onPressed: () => context.pop(),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  // Summary layout: Summary, Key points, Important information
  Widget _buildSummaryContent(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Executive Summary
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Executive Summary',
                style: AppTypography.subsectionTitle.copyWith(
                  color: isDark ? AppColors.darkText : AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This document compiles comprehensive lecture principles and analytical formulations. The primary focus centers on physical dynamics, motion derivations, and empirical observation tables recorded during experimental testing.',
                style: AppTypography.body.copyWith(
                  color: isDark ? AppColors.darkText : AppColors.textPrimary,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 2. Key points
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Key Points',
                style: AppTypography.subsectionTitle.copyWith(
                  color: isDark ? AppColors.darkText : AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              _buildBulletItem('Newton\'s Second Law formulated as rate of change of momentum (F = dp/dt).', isDark),
              _buildBulletItem('Gravitational potential energy verified across 4 distinct heights.', isDark),
              _buildBulletItem('Error margins constrained to less than 2.3% during calibration.', isDark),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 3. Important information
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Important Information',
                style: AppTypography.subsectionTitle.copyWith(
                  color: isDark ? AppColors.darkText : AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Final test equations on page 6 require standard SI units. Make sure all mass measurements are converted from grams to kilograms prior to final evaluation.',
                style: AppTypography.body.copyWith(
                  color: isDark ? AppColors.darkText : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildExplainContent(bool isDark) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Simplified Explanation',
            style: AppTypography.subsectionTitle.copyWith(
              color: isDark ? AppColors.darkText : AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Think of this document like a recipe for understanding motion. Whenever something pushes an object, it speeds up depending on how heavy it is. Heavy things need bigger pushes, while light things speed up quickly with small nudges.',
            style: AppTypography.body.copyWith(
              color: isDark ? AppColors.darkText : AppColors.textPrimary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          _buildBulletItem('Simple Rule 1: More weight = More effort needed to move.', isDark),
          _buildBulletItem('Simple Rule 2: Constant speed means all opposing forces are balanced.', isDark),
        ],
      ),
    );
  }

  Widget _buildExtractContent(bool isDark) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Extracted Data & Tables',
            style: AppTypography.subsectionTitle.copyWith(
              color: isDark ? AppColors.darkText : AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Table(
            border: TableBorder.all(color: isDark ? AppColors.darkBorder : AppColors.border, width: 0.8),
            children: [
              TableRow(
                decoration: BoxDecoration(color: isDark ? const Color(0xFF262C34) : const Color(0xFFF1F5F9)),
                children: [
                  _buildTableCell('Parameter', isHeader: true, isDark: isDark),
                  _buildTableCell('Value', isHeader: true, isDark: isDark),
                  _buildTableCell('Unit', isHeader: true, isDark: isDark),
                ],
              ),
              TableRow(
                children: [
                  _buildTableCell('Mass (m)', isDark: isDark),
                  _buildTableCell('2.50', isDark: isDark),
                  _buildTableCell('kg', isDark: isDark),
                ],
              ),
              TableRow(
                children: [
                  _buildTableCell('Acceleration (a)', isDark: isDark),
                  _buildTableCell('9.81', isDark: isDark),
                  _buildTableCell('m/s²', isDark: isDark),
                ],
              ),
              TableRow(
                children: [
                  _buildTableCell('Net Force (F)', isDark: isDark),
                  _buildTableCell('24.52', isDark: isDark),
                  _buildTableCell('N', isDark: isDark),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNotesContent(bool isDark) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Study Notes',
            style: AppTypography.subsectionTitle.copyWith(
              color: isDark ? AppColors.darkText : AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          _buildBulletItem('Review pages 1–3 for formula definitions.', isDark),
          _buildBulletItem('Memorize constant acceleration equations.', isDark),
          _buildBulletItem('Complete question 4 on page 7 for weekly assignment.', isDark),
        ],
      ),
    );
  }

  Widget _buildGenericContent(bool isDark) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Document Insights',
            style: AppTypography.subsectionTitle.copyWith(
              color: isDark ? AppColors.darkText : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Detailed analysis and answers generated specifically for this document.',
            style: AppTypography.body.copyWith(
              color: isDark ? AppColors.darkText : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBulletItem(String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• ', style: TextStyle(color: isDark ? AppColors.darkPrimary : AppColors.primary, fontSize: 16, fontWeight: FontWeight.bold)),
          Expanded(
            child: Text(
              text,
              style: AppTypography.body.copyWith(
                color: isDark ? AppColors.darkText : AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableCell(String text, {bool isHeader = false, required bool isDark}) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text(
        text,
        style: AppTypography.bodySmall.copyWith(
          color: isDark ? AppColors.darkText : AppColors.textPrimary,
          fontWeight: isHeader ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
    );
  }

  Widget _buildSkeletonLoading(bool isDark) {
    final color = isDark ? const Color(0xFF262C34) : const Color(0xFFF1F5F9);
    return Padding(
      padding: AppDimensions.screenPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 140, height: 24, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6))),
          const SizedBox(height: 20),
          Container(width: double.infinity, height: 120, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16))),
          const SizedBox(height: 16),
          Container(width: double.infinity, height: 160, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16))),
        ],
      ),
    );
  }
}
