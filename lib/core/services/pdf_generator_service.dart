import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../models/models.dart';

/// PDF Export Quality Presets based on professional scanning standards:
/// - Small: ~150 DPI, ideal for fast email / messaging share, JPEG quality ~86
/// - Standard: ~200 DPI, recommended balance for general archive, JPEG quality ~90
/// - High: ~300 DPI, maximum archival clarity, JPEG quality ~94
enum PdfExportQuality {
  small,
  standard,
  high;

  int get targetDpi => switch (this) {
        PdfExportQuality.small => 150,
        PdfExportQuality.standard => 200,
        PdfExportQuality.high => 300,
      };

  int get jpegQuality => switch (this) {
        PdfExportQuality.small => 86,
        PdfExportQuality.standard => 90,
        PdfExportQuality.high => 94,
      };

  int get maxDimension => switch (this) {
        PdfExportQuality.small => 1754,
        PdfExportQuality.standard => 2338,
        PdfExportQuality.high => 3508,
      };

  String get label => switch (this) {
        PdfExportQuality.small => 'Small (~150 DPI)',
        PdfExportQuality.standard => 'Standard (~200 DPI)',
        PdfExportQuality.high => 'High (~300 DPI)',
      };

  static PdfExportQuality fromString(String? name) {
    return switch (name?.toLowerCase().trim()) {
      'small' => PdfExportQuality.small,
      'high' => PdfExportQuality.high,
      _ => PdfExportQuality.standard,
    };
  }
}

/// Service for generating real, multi-page PDF files on device
/// with configurable export quality and natural document aspect preservation.
class PdfGeneratorService {
  /// Generates a real multi-page PDF file from [pages] at [outputPath].
  static Future<File> generatePdf({
    required List<DocumentPage> pages,
    required String outputPath,
    String? documentTitle,
    PdfExportQuality quality = PdfExportQuality.standard,
    PdfPageFormat? pageFormat,
  }) async {
    final pdf = pw.Document(
      title: documentTitle ?? 'DocuRay Scanned Document',
      author: 'DocuRay',
      creator: 'DocuRay Document Scanner',
    );

    for (final page in pages) {
      final imgPath = page.processedImagePath ?? page.originalImagePath;
      if (imgPath == null) continue;

      final file = File(imgPath);
      if (!await file.exists()) continue;

      final rawBytes = await file.readAsBytes();
      final decoded = img.decodeImage(rawBytes);
      if (decoded == null) continue;

      // Downscale to target DPI if necessary, NEVER upscale low-res images
      var pageImg = decoded;
      final maxDim = quality.maxDimension;
      if (pageImg.width > maxDim || pageImg.height > maxDim) {
        final isWLonger = pageImg.width >= pageImg.height;
        pageImg = img.copyResize(
          pageImg,
          width: isWLonger ? maxDim : null,
          height: !isWLonger ? maxDim : null,
          interpolation: img.Interpolation.linear,
        );
      }

      // Encode image bytes according to preset and filter type
      List<int> encodedBytes;
      if (page.filterType.toLowerCase() == 'bw') {
        // High compression for binary text
        encodedBytes = img.encodeJpg(pageImg, quality: 85);
      } else {
        encodedBytes = img.encodeJpg(pageImg, quality: quality.jpegQuality);
      }

      final image = pw.MemoryImage(Uint8List.fromList(encodedBytes));

      // Calculate natural document aspect ratio
      final double aspect = pageImg.width / pageImg.height;
      final PdfPageFormat effectiveFormat;

      if (pageFormat != null) {
        effectiveFormat = pageFormat;
      } else if ((aspect - (210.0 / 297.0)).abs() < 0.12) {
        // Close to standard portrait A4
        effectiveFormat = PdfPageFormat.a4;
      } else if ((aspect - (297.0 / 210.0)).abs() < 0.12) {
        // Close to standard landscape A4
        effectiveFormat = PdfPageFormat.a4.landscape;
      } else {
        // Natural document proportions (receipts, ID cards, business cards)
        const double baseWidth = 595.28; // Standard A4 width in points
        final double baseHeight = (baseWidth / aspect).clamp(200.0, 1600.0);
        effectiveFormat = PdfPageFormat(baseWidth, baseHeight);
      }

      pdf.addPage(
        pw.Page(
          pageFormat: effectiveFormat,
          margin: pw.EdgeInsets.zero,
          build: (pw.Context context) {
            return pw.FullPage(
              ignoreMargins: true,
              child: pw.Center(
                child: pw.Image(
                  image,
                  fit: pw.BoxFit.contain,
                ),
              ),
            );
          },
        ),
      );
    }

    final outputFile = File(outputPath);
    final bytes = await pdf.save();
    await outputFile.writeAsBytes(bytes, flush: true);
    return outputFile;
  }

  /// Formats byte count into human-readable string (e.g. "840 KB", "2.1 MB")
  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
