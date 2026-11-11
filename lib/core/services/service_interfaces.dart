import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Camera service interface for future hardware camera integration.
abstract class CameraService {
  Future<void> initialize();
  Future<void> dispose();
  Future<void> setFlashMode(bool enabled);
  Future<Uint8List> capturePhoto();
  bool get isInitialized;
}

/// Corner detection interface for future ML-based edge and document detection.
abstract class CornerDetectionService {
  Future<List<Offset>> detectCorners(Uint8List imageBytes);
  Future<bool> isDocumentDetected(Uint8List imageBytes);
}

/// Image processing interface for perspective transform, filtering, adjustments.
abstract class ImageProcessingService {
  Future<Uint8List> cropAndTransform(Uint8List imageBytes, List<Offset> corners);
  Future<Uint8List> applyFilter(Uint8List imageBytes, String filterType);
  Future<Uint8List> adjustImage(Uint8List imageBytes, {double brightness = 0.0, double contrast = 0.0, double sharpness = 0.0});
}

/// PDF generation and manipulation service.
abstract class PdfService {
  Future<String> createPdfFromPages(List<Uint8List> pages, {String quality = 'Standard'});
  Future<int> getPageCount(String pdfPath);
}

/// OCR text extraction service.
abstract class OcrService {
  Future<String> extractText(Uint8List imageBytes);
}

/// Google Drive cloud backup and sync service.
abstract class DriveService {
  Future<bool> connect();
  Future<void> disconnect();
  Future<bool> get isConnected;
  Future<String?> get userEmail;
  Future<bool> uploadDocument(String filePath, String destinationFolder);
  Future<void> syncAll();
}

/// AI assistant service for contextual document Q&A and quick actions.
abstract class AiService {
  Future<String> askQuestion({required String documentId, required String question, required String contextText});
  Future<String> summarizeDocument({required String documentId, required String contextText});
  Future<String> explainSimply({required String documentId, required String contextText});
  Future<String> extractInformation({required String documentId, required String contextText});
  Future<String> translateDocument({required String documentId, required String contextText, required String targetLanguage});
  Future<String> createNotes({required String documentId, required String contextText});
}
