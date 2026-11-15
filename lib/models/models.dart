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

/// A freehand erasing stroke applied to a document page.
class EraseStroke {
  final List<Offset> points;
  final double strokeWidth;

  const EraseStroke({required this.points, this.strokeWidth = 20.0});

  Map<String, dynamic> toJson() => {
    'points': points.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
    'strokeWidth': strokeWidth,
  };

  factory EraseStroke.fromJson(Map<String, dynamic> json) {
    return EraseStroke(
      points: (json['points'] as List<dynamic>?)
              ?.map((p) => Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble()))
              .toList() ?? [],
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 20.0,
    );
  }
}

/// Type of annotation drawn on a page.
enum AnnotationType {
  pen,
  highlighter,
  text,
  rectangle,
  circle,
  line,
  arrow,
  signature,
}

/// An individual vector or text annotation placed on a page.
class AnnotationElement {
  final String id;
  final AnnotationType type;
  final List<Offset> points; // Normalized 0.0 - 1.0 points
  final String? text;
  final int colorValue;
  final double strokeWidth;
  final double fontSize;

  const AnnotationElement({
    required this.id,
    required this.type,
    required this.points,
    this.text,
    this.colorValue = 0xFFFF0000,
    this.strokeWidth = 3.0,
    this.fontSize = 18.0,
  });

  Color get color => Color(colorValue);

  AnnotationElement copyWith({
    String? id,
    AnnotationType? type,
    List<Offset>? points,
    String? text,
    int? colorValue,
    double? strokeWidth,
    double? fontSize,
  }) {
    return AnnotationElement(
      id: id ?? this.id,
      type: type ?? this.type,
      points: points ?? this.points,
      text: text ?? this.text,
      colorValue: colorValue ?? this.colorValue,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      fontSize: fontSize ?? this.fontSize,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'points': points.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
    if (text != null) 'text': text,
    'colorValue': colorValue,
    'strokeWidth': strokeWidth,
    'fontSize': fontSize,
  };

  factory AnnotationElement.fromJson(Map<String, dynamic> json) {
    return AnnotationElement(
      id: json['id'] as String? ?? 'ann_${DateTime.now().microsecondsSinceEpoch}',
      type: AnnotationType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => AnnotationType.pen,
      ),
      points: (json['points'] as List<dynamic>?)
              ?.map((p) => Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble()))
              .toList() ?? [],
      text: json['text'] as String?,
      colorValue: json['colorValue'] as int? ?? 0xFFFF0000,
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 3.0,
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 18.0,
    );
  }
}

/// Configuration for text or image watermark.
class WatermarkConfig {
  final bool enabled;
  final String type; // 'text' or 'image'
  final String text;
  final double fontSize;
  final int colorValue;
  final double opacity;
  final double rotation; // In degrees
  final String position; // 'diagonal', 'center', 'top', 'bottom'
  final String? imagePath;
  final double imageScale;

  const WatermarkConfig({
    this.enabled = false,
    this.type = 'text',
    this.text = 'CONFIDENTIAL',
    this.fontSize = 32.0,
    this.colorValue = 0x6694A3B8,
    this.opacity = 0.35,
    this.rotation = -35.0,
    this.position = 'diagonal',
    this.imagePath,
    this.imageScale = 0.5,
  });

  Color get color => Color(colorValue);

  WatermarkConfig copyWith({
    bool? enabled,
    String? type,
    String? text,
    double? fontSize,
    int? colorValue,
    double? opacity,
    double? rotation,
    String? position,
    String? imagePath,
    double? imageScale,
  }) {
    return WatermarkConfig(
      enabled: enabled ?? this.enabled,
      type: type ?? this.type,
      text: text ?? this.text,
      fontSize: fontSize ?? this.fontSize,
      colorValue: colorValue ?? this.colorValue,
      opacity: opacity ?? this.opacity,
      rotation: rotation ?? this.rotation,
      position: position ?? this.position,
      imagePath: imagePath ?? this.imagePath,
      imageScale: imageScale ?? this.imageScale,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'type': type,
    'text': text,
    'fontSize': fontSize,
    'colorValue': colorValue,
    'opacity': opacity,
    'rotation': rotation,
    'position': position,
    if (imagePath != null) 'imagePath': imagePath,
    'imageScale': imageScale,
  };

  factory WatermarkConfig.fromJson(Map<String, dynamic> json) {
    return WatermarkConfig(
      enabled: json['enabled'] as bool? ?? false,
      type: json['type'] as String? ?? 'text',
      text: json['text'] as String? ?? 'CONFIDENTIAL',
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 32.0,
      colorValue: json['colorValue'] as int? ?? 0x6694A3B8,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 0.35,
      rotation: (json['rotation'] as num?)?.toDouble() ?? -35.0,
      position: json['position'] as String? ?? 'diagonal',
      imagePath: json['imagePath'] as String?,
      imageScale: (json['imageScale'] as num?)?.toDouble() ?? 0.5,
    );
  }
}

/// A rectangular region on a page that is permanently redacted.
class RedactionRect {
  final String id;
  final double left; // Normalized 0.0 - 1.0
  final double top;
  final double width;
  final double height;

  const RedactionRect({
    required this.id,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  Rect toRect(Size size) => Rect.fromLTWH(
    left * size.width,
    top * size.height,
    width * size.width,
    height * size.height,
  );

  RedactionRect copyWith({
    String? id,
    double? left,
    double? top,
    double? width,
    double? height,
  }) {
    return RedactionRect(
      id: id ?? this.id,
      left: left ?? this.left,
      top: top ?? this.top,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'left': left,
    'top': top,
    'width': width,
    'height': height,
  };

  factory RedactionRect.fromJson(Map<String, dynamic> json) {
    return RedactionRect(
      id: json['id'] as String? ?? 'redact_${DateTime.now().microsecondsSinceEpoch}',
      left: (json['left'] as num).toDouble(),
      top: (json['top'] as num).toDouble(),
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
    );
  }
}

/// Page resizing and target paper dimension preset.
class PageResizeConfig {
  final String preset; // 'original', 'a4', 'a5', 'letter', 'legal', 'custom'
  final double? customWidth;
  final double? customHeight;

  const PageResizeConfig({
    this.preset = 'original',
    this.customWidth,
    this.customHeight,
  });

  PageResizeConfig copyWith({
    String? preset,
    double? customWidth,
    double? customHeight,
  }) {
    return PageResizeConfig(
      preset: preset ?? this.preset,
      customWidth: customWidth ?? this.customWidth,
      customHeight: customHeight ?? this.customHeight,
    );
  }

  Map<String, dynamic> toJson() => {
    'preset': preset,
    if (customWidth != null) 'customWidth': customWidth,
    if (customHeight != null) 'customHeight': customHeight,
  };

  factory PageResizeConfig.fromJson(Map<String, dynamic> json) {
    return PageResizeConfig(
      preset: json['preset'] as String? ?? 'original',
      customWidth: (json['customWidth'] as num?)?.toDouble(),
      customHeight: (json['customHeight'] as num?)?.toDouble(),
    );
  }
}

/// Margin insets (in points) around page content.
class PageMargins {
  final double top;
  final double bottom;
  final double left;
  final double right;

  const PageMargins({
    this.top = 0.0,
    this.bottom = 0.0,
    this.left = 0.0,
    this.right = 0.0,
  });

  bool get hasMargins => top > 0 || bottom > 0 || left > 0 || right > 0;

  PageMargins copyWith({
    double? top,
    double? bottom,
    double? left,
    double? right,
  }) {
    return PageMargins(
      top: top ?? this.top,
      bottom: bottom ?? this.bottom,
      left: left ?? this.left,
      right: right ?? this.right,
    );
  }

  Map<String, dynamic> toJson() => {
    'top': top,
    'bottom': bottom,
    'left': left,
    'right': right,
  };

  factory PageMargins.fromJson(Map<String, dynamic> json) {
    return PageMargins(
      top: (json['top'] as num?)?.toDouble() ?? 0.0,
      bottom: (json['bottom'] as num?)?.toDouble() ?? 0.0,
      left: (json['left'] as num?)?.toDouble() ?? 0.0,
      right: (json['right'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Border applied around a scanned document page.
class PageBorder {
  final bool enabled;
  final double thickness;
  final int colorValue;
  final String style; // 'solid', 'dashed', 'double'

  const PageBorder({
    this.enabled = false,
    this.thickness = 2.0,
    this.colorValue = 0xFF000000,
    this.style = 'solid',
  });

  Color get color => Color(colorValue);

  PageBorder copyWith({
    bool? enabled,
    double? thickness,
    int? colorValue,
    String? style,
  }) {
    return PageBorder(
      enabled: enabled ?? this.enabled,
      thickness: thickness ?? this.thickness,
      colorValue: colorValue ?? this.colorValue,
      style: style ?? this.style,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'thickness': thickness,
    'colorValue': colorValue,
    'style': style,
  };

  factory PageBorder.fromJson(Map<String, dynamic> json) {
    return PageBorder(
      enabled: json['enabled'] as bool? ?? false,
      thickness: (json['thickness'] as num?)?.toDouble() ?? 2.0,
      colorValue: json['colorValue'] as int? ?? 0xFF000000,
      style: json['style'] as String? ?? 'solid',
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
  final String filterType; // 'original', 'auto', 'light_text', 'grayscale', 'whiteboard', 'bw'
  final double brightness; // -1.0 to 1.0
  final double contrast;   // -1.0 to 1.0
  final double sharpness;  // 0.0 to 1.0
  final double highlights; // -1.0 to 1.0
  final double shadows;    // -1.0 to 1.0
  final double exposure;   // -1.0 to 1.0
  final double saturation; // -1.0 to 1.0
  final List<CornerPoint> corners;
  final List<CornerPoint>? autoDetectedCorners;
  final int? imageWidth;
  final int? imageHeight;

  // 16 Tools Persistent State
  final List<EraseStroke> eraseStrokes;
  final List<AnnotationElement> annotations;
  final WatermarkConfig watermark;
  final List<RedactionRect> redactions;
  final PageResizeConfig resize;
  final PageMargins margins;
  final PageBorder border;

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
    this.highlights = 0.0,
    this.shadows = 0.0,
    this.exposure = 0.0,
    this.saturation = 0.0,
    this.corners = const [
      CornerPoint(0.05, 0.05),
      CornerPoint(0.95, 0.05),
      CornerPoint(0.95, 0.95),
      CornerPoint(0.05, 0.95),
    ],
    this.autoDetectedCorners,
    this.imageWidth,
    this.imageHeight,
    this.eraseStrokes = const [],
    this.annotations = const [],
    this.watermark = const WatermarkConfig(),
    this.redactions = const [],
    this.resize = const PageResizeConfig(),
    this.margins = const PageMargins(),
    this.border = const PageBorder(),
  });

  /// Upright aspect ratio (width / height) based on actual oriented image dimensions
  double get aspectRatio =>
      (imageWidth != null && imageHeight != null && imageHeight! > 0)
          ? (imageWidth! / imageHeight!)
          : (3.0 / 4.0);

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
    double? highlights,
    double? shadows,
    double? exposure,
    double? saturation,
    List<CornerPoint>? corners,
    List<CornerPoint>? autoDetectedCorners,
    int? imageWidth,
    int? imageHeight,
    List<EraseStroke>? eraseStrokes,
    List<AnnotationElement>? annotations,
    WatermarkConfig? watermark,
    List<RedactionRect>? redactions,
    PageResizeConfig? resize,
    PageMargins? margins,
    PageBorder? border,
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
      highlights: highlights ?? this.highlights,
      shadows: shadows ?? this.shadows,
      exposure: exposure ?? this.exposure,
      saturation: saturation ?? this.saturation,
      corners: corners ?? this.corners,
      autoDetectedCorners: autoDetectedCorners ?? this.autoDetectedCorners,
      imageWidth: imageWidth ?? this.imageWidth,
      imageHeight: imageHeight ?? this.imageHeight,
      eraseStrokes: eraseStrokes ?? this.eraseStrokes,
      annotations: annotations ?? this.annotations,
      watermark: watermark ?? this.watermark,
      redactions: redactions ?? this.redactions,
      resize: resize ?? this.resize,
      margins: margins ?? this.margins,
      border: border ?? this.border,
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
    'highlights': highlights,
    'shadows': shadows,
    'exposure': exposure,
    'saturation': saturation,
    'corners': corners.map((c) => c.toJson()).toList(),
    if (autoDetectedCorners != null)
      'autoDetectedCorners': autoDetectedCorners!.map((c) => c.toJson()).toList(),
    if (imageWidth != null) 'imageWidth': imageWidth,
    if (imageHeight != null) 'imageHeight': imageHeight,
    if (eraseStrokes.isNotEmpty)
      'eraseStrokes': eraseStrokes.map((s) => s.toJson()).toList(),
    if (annotations.isNotEmpty)
      'annotations': annotations.map((a) => a.toJson()).toList(),
    if (watermark.enabled)
      'watermark': watermark.toJson(),
    if (redactions.isNotEmpty)
      'redactions': redactions.map((r) => r.toJson()).toList(),
    if (resize.preset != 'original')
      'resize': resize.toJson(),
    if (margins.hasMargins)
      'margins': margins.toJson(),
    if (border.enabled)
      'border': border.toJson(),
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
      highlights: (json['highlights'] as num?)?.toDouble() ?? 0.0,
      shadows: (json['shadows'] as num?)?.toDouble() ?? 0.0,
      exposure: (json['exposure'] as num?)?.toDouble() ?? 0.0,
      saturation: (json['saturation'] as num?)?.toDouble() ?? 0.0,
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
      imageWidth: json['imageWidth'] as int?,
      imageHeight: json['imageHeight'] as int?,
      eraseStrokes: (json['eraseStrokes'] as List<dynamic>?)
              ?.map((s) => EraseStroke.fromJson(s as Map<String, dynamic>))
              .toList() ??
          const [],
      annotations: (json['annotations'] as List<dynamic>?)
              ?.map((a) => AnnotationElement.fromJson(a as Map<String, dynamic>))
              .toList() ??
          const [],
      watermark: json['watermark'] != null
          ? WatermarkConfig.fromJson(json['watermark'] as Map<String, dynamic>)
          : const WatermarkConfig(),
      redactions: (json['redactions'] as List<dynamic>?)
              ?.map((r) => RedactionRect.fromJson(r as Map<String, dynamic>))
              .toList() ??
          const [],
      resize: json['resize'] != null
          ? PageResizeConfig.fromJson(json['resize'] as Map<String, dynamic>)
          : const PageResizeConfig(),
      margins: json['margins'] != null
          ? PageMargins.fromJson(json['margins'] as Map<String, dynamic>)
          : const PageMargins(),
      border: json['border'] != null
          ? PageBorder.fromJson(json['border'] as Map<String, dynamic>)
          : const PageBorder(),
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

  Folder copyWith({
    String? id,
    String? name,
    Color? color,
    IconData? icon,
    DateTime? createdAt,
  }) {
    return Folder(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      icon: icon ?? this.icon,
      createdAt: createdAt ?? this.createdAt,
    );
  }

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
  final List<String>? attachedImagePaths;

  const AIMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.isLoading = false,
    this.hasError = false,
    this.quickActionType,
    this.attachedImagePaths,
  });

  AIMessage copyWith({
    String? id,
    MessageRole? role,
    String? content,
    DateTime? timestamp,
    bool? isLoading,
    bool? hasError,
    String? quickActionType,
    List<String>? attachedImagePaths,
  }) {
    return AIMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      isLoading: isLoading ?? this.isLoading,
      hasError: hasError ?? this.hasError,
      quickActionType: quickActionType ?? this.quickActionType,
      attachedImagePaths: attachedImagePaths ?? this.attachedImagePaths,
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
