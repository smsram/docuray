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
  /// When [isPreCompressed] is true, avoids redundant decoding/encoding in Dart and
  /// embeds raw JPEG bytes directly into the PDF in milliseconds.
  static Future<File> generatePdf({
    required List<DocumentPage> pages,
    required String outputPath,
    String? documentTitle,
    PdfExportQuality quality = PdfExportQuality.standard,
    PdfPageFormat? pageFormat,
    bool isPreCompressed = false,
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
      final pw.MemoryImage image;
      final double aspect;

      if (isPreCompressed) {
        // Fast, zero-heap-overhead direct embedding:
        // Already pre-scaled and encoded with target quality by the export pipeline
        image = pw.MemoryImage(rawBytes);
        final decoder = img.findDecoderForData(rawBytes);
        final info = decoder?.startDecode(rawBytes);
        if (info != null && info.height > 0) {
          aspect = info.width / info.height;
        } else if (page.imageWidth != null && page.imageHeight != null && page.imageHeight! > 0) {
          aspect = page.imageWidth! / page.imageHeight!;
        } else {
          aspect = 3.0 / 4.0;
        }
      } else {
        // Fallback for direct non-precompressed generation (e.g. unit tests):
        final decoded = img.decodeImage(rawBytes);
        if (decoded == null) continue;

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

        final List<int> encodedBytes;
        if (page.filterType.toLowerCase() == 'bw') {
          // High compression for binary text
          encodedBytes = img.encodeJpg(pageImg, quality: 85);
        } else {
          encodedBytes = img.encodeJpg(pageImg, quality: quality.jpegQuality);
        }

        image = pw.MemoryImage(Uint8List.fromList(encodedBytes));
        aspect = pageImg.width / pageImg.height;
      }

      // Determine PDF page format based on page.resize config or fallback aspect
      final PdfPageFormat effectiveFormat;
      if (pageFormat != null) {
        effectiveFormat = pageFormat;
      } else {
        switch (page.resize.preset.toLowerCase()) {
          case 'a4':
            effectiveFormat = (aspect > 1.0) ? PdfPageFormat.a4.landscape : PdfPageFormat.a4;
            break;
          case 'a5':
            effectiveFormat = (aspect > 1.0) ? PdfPageFormat.a5.landscape : PdfPageFormat.a5;
            break;
          case 'letter':
            effectiveFormat = (aspect > 1.0) ? PdfPageFormat.letter.landscape : PdfPageFormat.letter;
            break;
          case 'legal':
            effectiveFormat = (aspect > 1.0) ? PdfPageFormat.legal.landscape : PdfPageFormat.legal;
            break;
          case 'custom':
            final w = page.resize.customWidth ?? 595.28;
            final h = page.resize.customHeight ?? 841.89;
            effectiveFormat = PdfPageFormat(w, h);
            break;
          case 'original':
          default:
            if ((aspect - (210.0 / 297.0)).abs() < 0.12) {
              effectiveFormat = PdfPageFormat.a4;
            } else if ((aspect - (297.0 / 210.0)).abs() < 0.12) {
              effectiveFormat = PdfPageFormat.a4.landscape;
            } else {
              const double baseWidth = 595.28;
              final double baseHeight = (baseWidth / aspect).clamp(200.0, 1600.0);
              effectiveFormat = PdfPageFormat(baseWidth, baseHeight);
            }
            break;
        }
      }

      // Build page content with optional margins, borders, and watermark
      pdf.addPage(
        pw.Page(
          pageFormat: effectiveFormat,
          margin: pw.EdgeInsets.zero,
          build: (pw.Context context) {
            pw.Widget content = pw.Center(
              child: pw.Image(
                image,
                fit: pw.BoxFit.contain,
              ),
            );

            // Apply page border if enabled
            if (page.border.enabled) {
              final borderColor = PdfColor.fromInt(page.border.colorValue);
              final thickness = page.border.thickness.clamp(0.5, 12.0);
              content = pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(
                    color: borderColor,
                    width: thickness,
                  ),
                ),
                child: content,
              );
            }

            // Apply page margins if set
            if (page.margins.hasMargins) {
              content = pw.Padding(
                padding: pw.EdgeInsets.fromLTRB(
                  page.margins.left,
                  page.margins.top,
                  page.margins.right,
                  page.margins.bottom,
                ),
                child: content,
              );
            }

            // Apply watermark overlay if enabled
            if (page.watermark.enabled) {
              final wm = page.watermark;
              final baseColor = PdfColor.fromInt(wm.colorValue);
              final wmColor = PdfColor(baseColor.red, baseColor.green, baseColor.blue, wm.opacity);

              final watermarkWidget = pw.Center(
                child: pw.Transform.rotate(
                  angle: wm.rotation * (3.141592653589793 / 180.0),
                  child: pw.Text(
                    wm.text,
                    style: pw.TextStyle(
                      color: wmColor,
                      fontSize: wm.fontSize,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              );

              content = pw.Stack(
                fit: pw.StackFit.expand,
                children: [
                  content,
                  watermarkWidget,
                ],
              );
            }

            return pw.FullPage(
              ignoreMargins: true,
              child: content,
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
