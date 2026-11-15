import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:docuray/models/models.dart';
import 'package:docuray/core/providers/editor_provider.dart';
import 'package:docuray/core/providers/settings_provider.dart';
import 'package:docuray/core/services/pdf_generator_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('docuray_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return tempDir.path;
      },
    );
  });

  tearDownAll(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('1. Editor Toolbar: 16 Tools Ordering & Enum Integrity', () {
    test('EditorActiveTool contains all 16 tools plus none', () {
      final tools = EditorActiveTool.values;
      expect(tools.length, 17); // none + 16 tools
      expect(tools[0], EditorActiveTool.none);
      expect(tools[1], EditorActiveTool.crop);
      expect(tools[2], EditorActiveTool.rotate);
      expect(tools[3], EditorActiveTool.filter);
      expect(tools[4], EditorActiveTool.adjust);
      expect(tools[5], EditorActiveTool.retake);
      expect(tools[6], EditorActiveTool.erase);
      expect(tools[7], EditorActiveTool.annotate);
      expect(tools[8], EditorActiveTool.watermark);
      expect(tools[9], EditorActiveTool.redact);
      expect(tools[10], EditorActiveTool.resize);
      expect(tools[11], EditorActiveTool.margins);
      expect(tools[12], EditorActiveTool.border);
      expect(tools[13], EditorActiveTool.reorder);
      expect(tools[14], EditorActiveTool.undo);
      expect(tools[15], EditorActiveTool.redo);
      expect(tools[16], EditorActiveTool.reset);
    });
  });

  group('2. Undo / Redo 30-Depth State Stack', () {
    test('Tracks at least 30 operations and undoes/redoes correctly', () {
      final editor = EditorProvider();
      final page1 = DocumentPage(id: 'p1', pageNumber: 1, filterType: 'original');
      editor.initializeWithPages([page1]);

      expect(editor.canUndo, false);
      expect(editor.canRedo, false);

      // Perform 35 sequential rotations
      for (int i = 0; i < 35; i++) {
        editor.rotateCurrentPage(clockwise: true);
      }

      // History should cap at 30
      expect(editor.canUndo, true);
      expect(editor.canRedo, false);

      // Current rotation after 35 * 90° = 3150° % 360 = 270°
      expect(editor.currentPage?.rotationDegrees, 270);

      // Undo 10 times
      for (int i = 0; i < 10; i++) {
        editor.undo();
      }
      expect(editor.canRedo, true);
      // 25 * 90° = 2250° % 360 = 90°
      expect(editor.currentPage?.rotationDegrees, 90);

      // Redo 5 times
      for (int i = 0; i < 5; i++) {
        editor.redo();
      }
      // 30 * 90° = 2700° % 360 = 180°
      expect(editor.currentPage?.rotationDegrees, 180);
    });
  });

  group('3. Apply to All: Restricted Strictly to 7 Tools', () {
    late EditorProvider editor;

    setUp(() {
      editor = EditorProvider();
      final pages = [
        DocumentPage(id: 'p1', pageNumber: 1, filterType: 'original'),
        DocumentPage(id: 'p2', pageNumber: 2, filterType: 'original'),
        DocumentPage(id: 'p3', pageNumber: 3, filterType: 'original'),
      ];
      editor.initializeWithPages(pages);
    });

    test('1. Apply Rotate to All updates all pages', () {
      editor.applyRotateToAll(90);
      for (final p in editor.pages) {
        expect(p.rotationDegrees, 90);
      }
    });

    test('2. Apply Filter to All updates all pages', () {
      editor.applyFilterToAll('grayscale');
      for (final p in editor.pages) {
        expect(p.filterType, 'grayscale');
      }
    });

    test('3. Apply Adjustments to All updates all pages', () {
      editor.applyAdjustmentsToAll(
        brightness: 0.2,
        contrast: 0.1,
        sharpness: 0.5,
        highlights: 0.1,
        shadows: -0.1,
        exposure: 0.15,
        saturation: 0.05,
      );
      for (final p in editor.pages) {
        expect(p.brightness, 0.2);
        expect(p.contrast, 0.1);
        expect(p.sharpness, 0.5);
        expect(p.highlights, 0.1);
        expect(p.shadows, -0.1);
        expect(p.exposure, 0.15);
        expect(p.saturation, 0.05);
      }
    });

    test('4. Apply Watermark to All updates all pages', () {
      const wm = WatermarkConfig(enabled: true, text: 'CONFIDENTIAL', opacity: 0.4);
      editor.applyWatermarkToAll(wm);
      for (final p in editor.pages) {
        expect(p.watermark.enabled, true);
        expect(p.watermark.text, 'CONFIDENTIAL');
        expect(p.watermark.opacity, 0.4);
      }
    });

    test('5. Apply Resize to All updates all pages', () {
      const resize = PageResizeConfig(preset: 'a4');
      editor.applyResizeToAll(resize);
      for (final p in editor.pages) {
        expect(p.resize.preset, 'a4');
      }
    });

    test('6. Apply Margins to All updates all pages', () {
      const margins = PageMargins(top: 20, bottom: 20, left: 15, right: 15);
      editor.applyMarginsToAll(margins);
      for (final p in editor.pages) {
        expect(p.margins.top, 20);
        expect(p.margins.bottom, 20);
        expect(p.margins.left, 15);
        expect(p.margins.right, 15);
      }
    });

    test('7. Apply Border to All updates all pages', () {
      const border = PageBorder(enabled: true, thickness: 3.0, style: 'dashed');
      editor.applyBorderToAll(border);
      for (final p in editor.pages) {
        expect(p.border.enabled, true);
        expect(p.border.thickness, 3.0);
        expect(p.border.style, 'dashed');
      }
    });
  });

  group('4. Reorder, Reset & In-Place Retake', () {
    test('ReorderPages changes sequence and updates pageNumbers', () {
      final editor = EditorProvider();
      final pages = [
        DocumentPage(id: 'page_A', pageNumber: 1),
        DocumentPage(id: 'page_B', pageNumber: 2),
        DocumentPage(id: 'page_C', pageNumber: 3),
      ];
      editor.initializeWithPages(pages);

      // Move page_A from index 0 to index 2
      editor.reorderPages(0, 3);
      expect(editor.pages[0].id, 'page_B');
      expect(editor.pages[0].pageNumber, 1);
      expect(editor.pages[1].id, 'page_C');
      expect(editor.pages[1].pageNumber, 2);
      expect(editor.pages[2].id, 'page_A');
      expect(editor.pages[2].pageNumber, 3);
    });

    test('ResetCurrentPage restores original settings', () {
      final editor = EditorProvider();
      final page = DocumentPage(
        id: 'p1',
        pageNumber: 1,
        rotationDegrees: 180,
        filterType: 'bw',
        brightness: 0.3,
        watermark: const WatermarkConfig(enabled: true),
        border: const PageBorder(enabled: true),
      );
      editor.initializeWithPages([page]);

      editor.resetCurrentPage();
      expect(editor.currentPage?.rotationDegrees, 0);
      expect(editor.currentPage?.filterType, 'original');
      expect(editor.currentPage?.brightness, 0.0);
      expect(editor.currentPage?.watermark.enabled, false);
      expect(editor.currentPage?.border.enabled, false);
    });

    test('ReplacePageWithCapture updates target page in-place preserving others', () {
      final editor = EditorProvider();
      final pages = [
        DocumentPage(id: 'p1', pageNumber: 1),
        DocumentPage(id: 'p2', pageNumber: 2),
      ];
      editor.initializeWithPages(pages);

      final retaken = DocumentPage(id: 'new_p1', pageNumber: 1, filterType: 'auto');
      editor.replacePageWithCapture(0, retaken);

      expect(editor.pages[0].pageNumber, 1);
      expect(editor.pages[0].filterType, 'auto');
      expect(editor.pages[1].id, 'p2');
    });
  });

  group('5. Editing Preferences Persistence & Application', () {
    test('SettingsProvider persists 6 switches and applies to new page', () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsProvider();
      await settings.initialize();

      // Check defaults
      expect(settings.rememberFilter, true);
      expect(settings.rememberAdjustments, true);
      expect(settings.rememberResize, true);
      expect(settings.rememberMargins, true);
      expect(settings.rememberBorder, true);
      expect(settings.rememberWatermark, false);

      // Record preferences from an edited page
      final editedPage = DocumentPage(
        id: 'edit_1',
        pageNumber: 1,
        filterType: 'whiteboard',
        brightness: 0.15,
        contrast: 0.10,
        watermark: const WatermarkConfig(enabled: true, text: 'SAMPLE'),
        resize: const PageResizeConfig(preset: 'letter'),
        margins: const PageMargins(top: 10, bottom: 10, left: 10, right: 10),
        border: const PageBorder(enabled: true, thickness: 4.0),
      );
      await settings.recordPreferencesFromPage(editedPage);

      // Apply to a new fresh page
      final freshPage = DocumentPage(id: 'fresh_1', pageNumber: 2);
      final applied = settings.applyPreferencesToNewPage(freshPage);

      expect(applied.filterType, 'whiteboard');
      expect(applied.brightness, 0.15);
      expect(applied.contrast, 0.10);
      expect(applied.resize.preset, 'letter');
      expect(applied.margins.top, 10);
      expect(applied.border.enabled, true);
      expect(applied.border.thickness, 4.0);
      // Watermark default was false, so should remain false
      expect(applied.watermark.enabled, false);
    });
  });

  group('6. Genuine Destructive Redaction & PDF Export Benchmark', () {
    test('Redaction permanently destroys underlying image pixels', () async {
      // Create a test image with white background (255, 255, 255)
      final testImg = img.Image(width: 200, height: 200);
      img.fill(testImg, color: img.ColorRgb8(255, 255, 255));
      final testPath = '${tempDir.path}/test_redaction_orig.jpg';
      await File(testPath).writeAsBytes(img.encodeJpg(testImg));

      final page = DocumentPage(
        id: 'redact_page',
        pageNumber: 1,
        filterType: 'original',
        originalImagePath: testPath,
        processedImagePath: testPath,
        redactions: [
          // Redact box covering (0.2..0.8, 0.2..0.8) -> (40..160, 40..160)
          RedactionRect(id: 'r1', left: 0.2, top: 0.2, width: 0.6, height: 0.6),
        ],
      );

      final editor = EditorProvider();
      editor.initializeWithPages([page]);

      // Save document
      final doc = await editor.saveDocument(exportQuality: PdfExportQuality.standard);
      expect(doc.pages.isNotEmpty, true);
      final processedPath = doc.pages.first.processedImagePath;
      expect(processedPath != null, true);

      // Read back processed image and verify pixels in redaction box are black (0, 0, 0)
      final processedBytes = await File(processedPath!).readAsBytes();
      final loadedImg = img.decodeImage(processedBytes)!;

      // Inside redacted region
      final centerPixel = loadedImg.getPixel(100, 100);
      expect(centerPixel.r, 0);
      expect(centerPixel.g, 0);
      expect(centerPixel.b, 0);

      // Outside redacted region (should still be white)
      final cornerPixel = loadedImg.getPixel(10, 10);
      expect(cornerPixel.r, 255);
      expect(cornerPixel.g, 255);
      expect(cornerPixel.b, 255);
    });

    test('PDF Export Benchmark: 4-page and 10-page precompressed export speeds', () async {
      // Generate synthetic 4 pages of JPEG bytes
      final testImg = img.Image(width: 800, height: 1100);
      img.fill(testImg, color: img.ColorRgb8(240, 240, 240));
      final jpgBytes = Uint8List.fromList(img.encodeJpg(testImg, quality: 80));

      final fourPages = <DocumentPage>[];
      for (int i = 0; i < 4; i++) {
        final path = '${tempDir.path}/bench_page_$i.jpg';
        await File(path).writeAsBytes(jpgBytes);
        fourPages.add(DocumentPage(
          id: 'bench_$i',
          pageNumber: i + 1,
          processedImagePath: path,
        ));
      }

      // 4-page export timing benchmark
      final sw4 = Stopwatch()..start();
      final out4 = '${tempDir.path}/out_4.pdf';
      final pdf4File = await PdfGeneratorService.generatePdf(
        pages: fourPages,
        outputPath: out4,
        quality: PdfExportQuality.standard,
        isPreCompressed: true,
      );
      sw4.stop();

      final pdf4Bytes = await pdf4File.readAsBytes();
      // Benchmark info: 4-page direct embedding time: ${sw4.elapsedMilliseconds}ms (${pdf4Bytes.length} bytes)
      // Must take < 2500ms (previously took > 120,000ms / 2 minutes)
      expect(sw4.elapsedMilliseconds, lessThan(2500));
      expect(pdf4Bytes.length, greaterThan(1000));

      // 10-page export timing benchmark
      final tenPages = <DocumentPage>[];
      for (int i = 0; i < 10; i++) {
        tenPages.add(DocumentPage(
          id: 'bench_10_$i',
          pageNumber: i + 1,
          processedImagePath: fourPages[i % 4].processedImagePath,
        ));
      }

      final sw10 = Stopwatch()..start();
      final out10 = '${tempDir.path}/out_10.pdf';
      final pdf10File = await PdfGeneratorService.generatePdf(
        pages: tenPages,
        outputPath: out10,
        quality: PdfExportQuality.standard,
        isPreCompressed: true,
      );
      sw10.stop();

      final pdf10Bytes = await pdf10File.readAsBytes();
      // Benchmark info: 10-page direct embedding time: ${sw10.elapsedMilliseconds}ms (${pdf10Bytes.length} bytes)
      // Must take < 5000ms
      expect(sw10.elapsedMilliseconds, lessThan(5000));
      expect(pdf10Bytes.length, greaterThan(2000));
    });
  });
}
