import 'package:flutter/material.dart';

/// Represents a single corner point in a normalized 0.0 - 1.0 coordinate space.
class CornerPoint {
  final double x;
  final double y;

  const CornerPoint(this.x, this.y);

  Offset toOffset(Size size) => Offset(x * size.width, y * size.height);

  CornerPoint copyWith({double? x, double? y}) {
    return CornerPoint(x ?? this.x, y ?? this.y);
  }

  Map<String, dynamic> toJson() => {'x': x, 'y': y};

  factory CornerPoint.fromJson(Map<String, dynamic> json) {
    return CornerPoint(
      (json['x'] as num).toDouble(),
      (json['y'] as num).toDouble(),
    );
  }
}

/// Represents individual page within a scanned document.
class DocumentPage {
  final String id;
  final int pageNumber;
  final String? originalImagePath;
  final String? processedImagePath;
  final String? thumbnailPath;
  final int rotationDegrees;
  final String filterType; // 'original', 'auto', 'color', 'grayscale', 'bw'
  final double brightness; // -1.0 to 1.0
  final double contrast;   // -1.0 to 1.0
  final double sharpness;  // 0.0 to 1.0
  final List<CornerPoint> corners;
  final List<CornerPoint>? autoDetectedCorners;

  const DocumentPage({
    required this.id,
    required this.pageNumber,
    this.originalImagePath,
    this.processedImagePath,
    this.thumbnailPath,
    this.rotationDegrees = 0,
    this.filterType = 'auto',
    this.brightness = 0.0,
    this.contrast = 0.0,
    this.sharpness = 0.0,
    this.corners = const [
      CornerPoint(0.05, 0.05),
      CornerPoint(0.95, 0.05),
      CornerPoint(0.95, 0.95),
      CornerPoint(0.05, 0.95),
    ],
    this.autoDetectedCorners,
  });

  /// Convenient backward-compatible getter for displaying the current page image
  String? get imagePath => processedImagePath ?? originalImagePath;

  DocumentPage copyWith({
    String? id,
    int? pageNumber,
    String? originalImagePath,
    String? processedImagePath,
    String? thumbnailPath,
    int? rotationDegrees,
    String? filterType,
    double? brightness,
    double? contrast,
    double? sharpness,
    List<CornerPoint>? corners,
    List<CornerPoint>? autoDetectedCorners,
  }) {
    return DocumentPage(
      id: id ?? this.id,
      pageNumber: pageNumber ?? this.pageNumber,
      originalImagePath: originalImagePath ?? this.originalImagePath,
      processedImagePath: processedImagePath ?? this.processedImagePath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
      filterType: filterType ?? this.filterType,
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      sharpness: sharpness ?? this.sharpness,
      corners: corners ?? this.corners,
      autoDetectedCorners: autoDetectedCorners ?? this.autoDetectedCorners,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'pageNumber': pageNumber,
    'originalImagePath': originalImagePath,
    'processedImagePath': processedImagePath,
    'thumbnailPath': thumbnailPath,
    'rotationDegrees': rotationDegrees,
    'filterType': filterType,
    'brightness': brightness,
    'contrast': contrast,
    'sharpness': sharpness,
    'corners': corners.map((c) => c.toJson()).toList(),
    if (autoDetectedCorners != null)
      'autoDetectedCorners': autoDetectedCorners!.map((c) => c.toJson()).toList(),
  };

  factory DocumentPage.fromJson(Map<String, dynamic> json) {
    return DocumentPage(
      id: json['id'] as String,
      pageNumber: json['pageNumber'] as int? ?? 1,
      originalImagePath: json['originalImagePath'] as String?,
      processedImagePath: json['processedImagePath'] as String?,
      thumbnailPath: json['thumbnailPath'] as String?,
      rotationDegrees: json['rotationDegrees'] as int? ?? 0,
      filterType: json['filterType'] as String? ?? 'auto',
      brightness: (json['brightness'] as num?)?.toDouble() ?? 0.0,
      contrast: (json['contrast'] as num?)?.toDouble() ?? 0.0,
      sharpness: (json['sharpness'] as num?)?.toDouble() ?? 0.0,
      corners: (json['corners'] as List<dynamic>?)
              ?.map((c) => CornerPoint.fromJson(c as Map<String, dynamic>))
              .toList() ??
          const [
            CornerPoint(0.05, 0.05),
            CornerPoint(0.95, 0.05),
            CornerPoint(0.95, 0.95),
            CornerPoint(0.05, 0.95),
          ],
      autoDetectedCorners: (json['autoDetectedCorners'] as List<dynamic>?)
          ?.map((c) => CornerPoint.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Cloud sync status.
enum SyncStatus {
  notSynced,
  syncing,
  synced,
  waitingForConnection,
  failed,
}

/// Cloud metadata for Google Drive sync.
class SyncMetadata {
  final SyncStatus status;
  final DateTime? lastSyncedAt;
  final String? driveFileId;

  const SyncMetadata({
    this.status = SyncStatus.notSynced,
    this.lastSyncedAt,
    this.driveFileId,
  });

  SyncMetadata copyWith({
    SyncStatus? status,
    DateTime? lastSyncedAt,
    String? driveFileId,
  }) {
    return SyncMetadata(
      status: status ?? this.status,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      driveFileId: driveFileId ?? this.driveFileId,
    );
  }

  Map<String, dynamic> toJson() => {
    'status': status.name,
    'lastSyncedAt': lastSyncedAt?.toIso8601String(),
    'driveFileId': driveFileId,
  };

  factory SyncMetadata.fromJson(Map<String, dynamic> json) {
    return SyncMetadata(
      status: SyncStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => SyncStatus.notSynced,
      ),
      lastSyncedAt: json['lastSyncedAt'] != null
          ? DateTime.tryParse(json['lastSyncedAt'] as String)
          : null,
      driveFileId: json['driveFileId'] as String?,
    );
  }
}

/// Document format type.
enum DocumentFormat {
  pdf,
  image,
}

/// Core Document entity.
class Document {
  final String id;
  final String title;
  final List<DocumentPage> pages;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isFavorite;
  final String? folderId;
  final DocumentFormat format;
  final SyncMetadata syncMetadata;
  final int fileSizeBytes;
  final String? ocrSummary;
  final String? pdfPath;
  final String? thumbnailPath;

  const Document({
    required this.id,
    required this.title,
    required this.pages,
    required this.createdAt,
    required this.updatedAt,
    this.isFavorite = false,
    this.folderId,
    this.format = DocumentFormat.pdf,
    this.syncMetadata = const SyncMetadata(),
    this.fileSizeBytes = 1024 * 1024,
    this.ocrSummary,
    this.pdfPath,
    this.thumbnailPath,
  });

  int get pageCount => pages.length;

  /// Effective thumbnail path (document thumbnailPath or first page's thumbnail/image)
  String? get effectiveThumbnailPath {
    if (thumbnailPath != null && thumbnailPath!.isNotEmpty) return thumbnailPath;
    if (pages.isNotEmpty) {
      return pages.first.thumbnailPath ?? pages.first.imagePath;
    }
    return null;
  }

  String get formattedSize {
    if (fileSizeBytes < 1024 * 1024) {
      return '${(fileSizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Document copyWith({
    String? id,
    String? title,
    List<DocumentPage>? pages,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isFavorite,
    String? folderId,
    DocumentFormat? format,
    SyncMetadata? syncMetadata,
    int? fileSizeBytes,
    String? ocrSummary,
    String? pdfPath,
    String? thumbnailPath,
  }) {
    return Document(
      id: id ?? this.id,
      title: title ?? this.title,
      pages: pages ?? this.pages,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isFavorite: isFavorite ?? this.isFavorite,
      folderId: folderId ?? this.folderId,
      format: format ?? this.format,
      syncMetadata: syncMetadata ?? this.syncMetadata,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      ocrSummary: ocrSummary ?? this.ocrSummary,
      pdfPath: pdfPath ?? this.pdfPath,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'pages': pages.map((p) => p.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'isFavorite': isFavorite,
    'folderId': folderId,
    'format': format.name,
    'syncMetadata': syncMetadata.toJson(),
    'fileSizeBytes': fileSizeBytes,
    'ocrSummary': ocrSummary,
    'pdfPath': pdfPath,
    'thumbnailPath': thumbnailPath,
  };

  factory Document.fromJson(Map<String, dynamic> json) {
    return Document(
      id: json['id'] as String,
      title: json['title'] as String,
      pages: (json['pages'] as List<dynamic>?)
              ?.map((p) => DocumentPage.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      isFavorite: json['isFavorite'] as bool? ?? false,
      folderId: json['folderId'] as String?,
      format: DocumentFormat.values.firstWhere(
        (f) => f.name == json['format'],
        orElse: () => DocumentFormat.pdf,
      ),
      syncMetadata: json['syncMetadata'] != null
          ? SyncMetadata.fromJson(json['syncMetadata'] as Map<String, dynamic>)
          : const SyncMetadata(),
      fileSizeBytes: json['fileSizeBytes'] as int? ?? 0,
      ocrSummary: json['ocrSummary'] as String?,
      pdfPath: json['pdfPath'] as String?,
      thumbnailPath: json['thumbnailPath'] as String?,
    );
  }
}

/// Folder entity for grouping documents.
class Folder {
  final String id;
  final String name;
  final Color color;
  final IconData icon;
  final DateTime createdAt;

  const Folder({
    required this.id,
    required this.name,
    this.color = const Color(0xFF2563EB),
    this.icon = Icons.folder_rounded,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'color': color.toARGB32(),
    'createdAt': createdAt.toIso8601String(),
  };

  factory Folder.fromJson(Map<String, dynamic> json) {
    return Folder(
      id: json['id'] as String,
      name: json['name'] as String,
      color: Color(json['color'] as int? ?? 0xFF2563EB),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

/// Message role for AI assistant.
enum MessageRole {
  user,
  assistant,
  system,
}

/// Single message in a contextual document conversation.
class AIMessage {
  final String id;
  final MessageRole role;
  final String content;
  final DateTime timestamp;
  final bool isLoading;
  final bool hasError;
  final String? quickActionType; // 'summarize', 'explain', 'extract', 'translate', 'notes'

  const AIMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.isLoading = false,
    this.hasError = false,
    this.quickActionType,
  });

  AIMessage copyWith({
    String? id,
    MessageRole? role,
    String? content,
    DateTime? timestamp,
    bool? isLoading,
    bool? hasError,
    String? quickActionType,
  }) {
    return AIMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      isLoading: isLoading ?? this.isLoading,
      hasError: hasError ?? this.hasError,
      quickActionType: quickActionType ?? this.quickActionType,
    );
  }
}

/// Contextual conversation thread associated with a document.
class AIConversation {
  final String documentId;
  final List<AIMessage> messages;

  const AIConversation({
    required this.documentId,
    this.messages = const [],
  });

  AIConversation copyWith({
    String? documentId,
    List<AIMessage>? messages,
  }) {
    return AIConversation(
      documentId: documentId ?? this.documentId,
      messages: messages ?? this.messages,
    );
  }
}
