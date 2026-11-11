import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../constants/app_dimensions.dart';

/// Renders a realistic scanned document thumbnail preview with paper styling,
/// realistic text lines, title bar, and multi-page stacked effect.
class DocumentThumbnail extends StatelessWidget {
  final int pageCount;
  final double width;
  final double height;
  final int rotationDegrees;
  final String? filterType;
  final int pageNumber;
  final bool isSelected;
  final String documentTitle;
  final String? imagePath;

  const DocumentThumbnail({
    super.key,
    this.pageCount = 1,
    this.width = 68.0,
    this.height = 92.0,
    this.rotationDegrees = 0,
    this.filterType,
    this.pageNumber = 1,
    this.isSelected = false,
    this.documentTitle = '',
    this.imagePath,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Filter-based tints for realistic paper preview
    Color paperColor;
    Color inkColor;
    Color headerColor;

    switch (filterType) {
      case 'bw':
        paperColor = Colors.white;
        inkColor = const Color(0xFF1E293B);
        headerColor = const Color(0xFF0F172A);
        break;
      case 'grayscale':
        paperColor = const Color(0xFFF1F5F9);
        inkColor = const Color(0xFF475569);
        headerColor = const Color(0xFF334155);
        break;
      case 'color':
        paperColor = const Color(0xFFFAFBFD);
        inkColor = const Color(0xFF1E3A8A);
        headerColor = const Color(0xFF2563EB);
        break;
      case 'original':
        paperColor = const Color(0xFFFFFBEB);
        inkColor = const Color(0xFF78350F);
        headerColor = const Color(0xFF92400E);
        break;
      case 'auto':
      default:
        paperColor = isDark ? const Color(0xFF262C34) : Colors.white;
        inkColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF4B5563);
        headerColor = isDark ? AppColors.darkPrimary : AppColors.primary;
        break;
    }

    final hasStackedPages = pageCount > 1;

    Widget pageSheet = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: paperColor,
        borderRadius: BorderRadius.circular(AppDimensions.radiusThumbnail),
        border: Border.all(
          color: isSelected
              ? (isDark ? AppColors.darkPrimary : AppColors.primary)
              : (isDark ? AppColors.darkBorder : const Color(0xFFE2E8F0)),
          width: isSelected ? 2.0 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 30 : 12),
            blurRadius: 4,
            offset: const Offset(0, 1.5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppDimensions.radiusThumbnail),
        child: (imagePath != null && File(imagePath!).existsSync())
            ? Image.file(
                File(imagePath!),
                width: width,
                height: height,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => CustomPaint(
                  size: Size(width, height),
                  painter: _PaperContentPainter(
                    headerColor: headerColor,
                    inkColor: inkColor,
                    pageNumber: pageNumber,
                    documentTitle: documentTitle,
                  ),
                ),
              )
            : CustomPaint(
                size: Size(width, height),
                painter: _PaperContentPainter(
                  headerColor: headerColor,
                  inkColor: inkColor,
                  pageNumber: pageNumber,
                  documentTitle: documentTitle,
                ),
              ),
      ),
    );

    if (rotationDegrees != 0) {
      pageSheet = RotatedBox(
        quarterTurns: (rotationDegrees ~/ 90) % 4,
        child: pageSheet,
      );
    }

    if (!hasStackedPages) {
      return pageSheet;
    }

    // Stacked effect for multi-page documents
    return SizedBox(
      width: width + 4,
      height: height + 4,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background page shadow
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E232A) : const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(AppDimensions.radiusThumbnail),
                border: Border.all(
                  color: isDark ? AppColors.darkBorder : const Color(0xFFCBD5E1),
                  width: 0.8,
                ),
              ),
            ),
          ),
          // Front page
          Positioned(
            left: 0,
            top: 0,
            child: pageSheet,
          ),
        ],
      ),
    );
  }
}

/// Custom painter to realistically render document layout (header, ruled lines, diagrams).
class _PaperContentPainter extends CustomPainter {
  final Color headerColor;
  final Color inkColor;
  final int pageNumber;
  final String documentTitle;

  _PaperContentPainter({
    required this.headerColor,
    required this.inkColor,
    required this.pageNumber,
    required this.documentTitle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = inkColor.withAlpha(60)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    final headerPaint = Paint()
      ..color = headerColor.withAlpha(160)
      ..style = PaintingStyle.fill;

    final accentPaint = Paint()
      ..color = headerColor.withAlpha(50)
      ..style = PaintingStyle.fill;

    final double marginX = size.width * 0.12;
    final double contentWidth = size.width - (marginX * 2);

    // Draw header bar
    final headerRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(marginX, size.height * 0.12, contentWidth * 0.65, size.height * 0.05),
      const Radius.circular(1.5),
    );
    canvas.drawRRect(headerRect, headerPaint);

    // Draw sub-header bar
    final subHeaderRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(marginX, size.height * 0.20, contentWidth * 0.40, size.height * 0.035),
      const Radius.circular(1.0),
    );
    canvas.drawRRect(subHeaderRect, accentPaint);

    // Draw simulated paragraph lines
    final lineSpacing = size.height * 0.07;
    double currentY = size.height * 0.30;

    // Line 1
    canvas.drawLine(
      Offset(marginX, currentY),
      Offset(marginX + contentWidth * 0.95, currentY),
      linePaint,
    );

    // Line 2
    currentY += lineSpacing;
    canvas.drawLine(
      Offset(marginX, currentY),
      Offset(marginX + contentWidth * 0.88, currentY),
      linePaint,
    );

    // Line 3
    currentY += lineSpacing;
    canvas.drawLine(
      Offset(marginX, currentY),
      Offset(marginX + contentWidth * 0.65, currentY),
      linePaint,
    );

    // Line 4 - block diagram simulation
    currentY += lineSpacing * 1.2;
    final blockRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(marginX, currentY, contentWidth * 0.95, size.height * 0.15),
      const Radius.circular(2.0),
    );
    canvas.drawRRect(blockRect, accentPaint);

    // Line 5 & 6 below diagram
    currentY += size.height * 0.15 + lineSpacing * 0.8;
    if (currentY < size.height * 0.88) {
      canvas.drawLine(
        Offset(marginX, currentY),
        Offset(marginX + contentWidth * 0.85, currentY),
        linePaint,
      );
    }

    currentY += lineSpacing;
    if (currentY < size.height * 0.88) {
      canvas.drawLine(
        Offset(marginX, currentY),
        Offset(marginX + contentWidth * 0.50, currentY),
        linePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PaperContentPainter oldDelegate) {
    return oldDelegate.headerColor != headerColor ||
        oldDelegate.inkColor != inkColor ||
        oldDelegate.pageNumber != pageNumber ||
        oldDelegate.documentTitle != documentTitle;
  }
}
