import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../models/models.dart';
import '../../../core/providers/editor_provider.dart';
import '../../../core/theme/app_colors.dart';

/// Interactive preview overlay rendering margins, borders, watermark, erase strokes,
/// annotations, and redactions directly on top of the document preview.
class EditorPreviewOverlay extends StatefulWidget {
  final EditorProvider editor;
  final DocumentPage page;
  final Size size;
  final double eraseBrushSize;
  final AnnotationType activeAnnotationType;
  final Color activeAnnotationColor;
  final double activeAnnotationStrokeWidth;

  const EditorPreviewOverlay({
    super.key,
    required this.editor,
    required this.page,
    required this.size,
    this.eraseBrushSize = 15.0,
    this.activeAnnotationType = AnnotationType.pen,
    this.activeAnnotationColor = const Color(0xFFFF0000),
    this.activeAnnotationStrokeWidth = 3.0,
  });

  @override
  State<EditorPreviewOverlay> createState() => _EditorPreviewOverlayState();
}

class _EditorPreviewOverlayState extends State<EditorPreviewOverlay> {
  List<Offset> _currentErasePoints = [];
  List<Offset> _currentAnnotatePoints = [];
  String? _selectedRedactionId;

  @override
  Widget build(BuildContext context) {
    final activeTool = widget.editor.activeTool;
    final w = widget.size.width;
    final h = widget.size.height;

    return SizedBox(
      width: w,
      height: h,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Static and custom painters (Border, Margins, Erase, Annotations, Watermark, Redactions)
          CustomPaint(
            size: widget.size,
            painter: _DocumentOverlayPainter(
              page: widget.page,
              activeTool: activeTool,
              currentErasePoints: _currentErasePoints,
              eraseBrushSize: widget.eraseBrushSize,
              currentAnnotatePoints: _currentAnnotatePoints,
              annotateType: widget.activeAnnotationType,
              annotateColor: widget.activeAnnotationColor,
              annotateStrokeWidth: widget.activeAnnotationStrokeWidth,
            ),
          ),

          // 2. Interactive Redaction Boxes (only in Redact tool mode)
          if (activeTool == EditorActiveTool.redact)
            ...widget.page.redactions.map((r) => _buildInteractiveRedactionBox(r, w, h)),

          // 3. Gesture Detector for Erase tool
          if (activeTool == EditorActiveTool.erase)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (details) {
                final local = details.localPosition;
                setState(() {
                  _currentErasePoints = [Offset(local.dx / w, local.dy / h)];
                });
              },
              onPanUpdate: (details) {
                final local = details.localPosition;
                setState(() {
                  _currentErasePoints.add(Offset(
                    (local.dx / w).clamp(0.0, 1.0),
                    (local.dy / h).clamp(0.0, 1.0),
                  ));
                });
              },
              onPanEnd: (_) {
                if (_currentErasePoints.isNotEmpty) {
                  widget.editor.addEraseStroke(
                    EraseStroke(
                      points: List.from(_currentErasePoints),
                      strokeWidth: widget.eraseBrushSize,
                    ),
                  );
                  setState(() {
                    _currentErasePoints = [];
                  });
                }
              },
            ),

          // 4. Gesture Detector for Annotate tool (Pen & Highlighter)
          if (activeTool == EditorActiveTool.annotate &&
              (widget.activeAnnotationType == AnnotationType.pen ||
                  widget.activeAnnotationType == AnnotationType.highlighter))
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (details) {
                final local = details.localPosition;
                setState(() {
                  _currentAnnotatePoints = [Offset(local.dx / w, local.dy / h)];
                });
              },
              onPanUpdate: (details) {
                final local = details.localPosition;
                setState(() {
                  _currentAnnotatePoints.add(Offset(
                    (local.dx / w).clamp(0.0, 1.0),
                    (local.dy / h).clamp(0.0, 1.0),
                  ));
                });
              },
              onPanEnd: (_) {
                if (_currentAnnotatePoints.isNotEmpty) {
                  widget.editor.addAnnotation(
                    AnnotationElement(
                      id: 'ann_${DateTime.now().microsecondsSinceEpoch}',
                      type: widget.activeAnnotationType,
                      points: List.from(_currentAnnotatePoints),
                      colorValue: widget.activeAnnotationColor.toARGB32(),
                      strokeWidth: widget.activeAnnotationStrokeWidth,
                    ),
                  );
                  setState(() {
                    _currentAnnotatePoints = [];
                  });
                }
              },
            ),
        ],
      ),
    );
  }

  Widget _buildInteractiveRedactionBox(RedactionRect r, double w, double h) {
    final isSelected = _selectedRedactionId == r.id;
    final boxLeft = r.left * w;
    final boxTop = r.top * h;
    final boxWidth = r.width * w;
    final boxHeight = r.height * h;

    return Positioned(
      left: boxLeft,
      top: boxTop,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedRedactionId = isSelected ? null : r.id;
          });
        },
        onPanUpdate: (details) {
          final newLeft = (boxLeft + details.delta.dx) / w;
          final newTop = (boxTop + details.delta.dy) / h;
          final updated = r.copyWith(
            left: newLeft.clamp(0.0, 1.0 - r.width),
            top: newTop.clamp(0.0, 1.0 - r.height),
          );
          final list = List<RedactionRect>.from(widget.page.redactions);
          final idx = list.indexWhere((item) => item.id == r.id);
          if (idx != -1) {
            list[idx] = updated;
            widget.editor.setRedactions(list);
          }
        },
        child: Container(
          width: boxWidth,
          height: boxHeight,
          decoration: BoxDecoration(
            color: Colors.black,
            border: Border.all(
              color: isSelected ? AppColors.primary : Colors.white70,
              width: isSelected ? 2.0 : 1.0,
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Delete badge on selected box
              if (isSelected)
                Positioned(
                  top: -12,
                  right: -12,
                  child: GestureDetector(
                    onTap: () => widget.editor.removeRedaction(r.id),
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(
                        color: AppColors.error,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                    ),
                  ),
                ),

              // Resize handle on selected box
              if (isSelected)
                Positioned(
                  bottom: -10,
                  right: -10,
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      final newW = ((boxWidth + details.delta.dx) / w).clamp(0.05, 1.0 - r.left);
                      final newH = ((boxHeight + details.delta.dy) / h).clamp(0.03, 1.0 - r.top);
                      final updated = r.copyWith(width: newW, height: newH);
                      final list = List<RedactionRect>.from(widget.page.redactions);
                      final idx = list.indexWhere((item) => item.id == r.id);
                      if (idx != -1) {
                        list[idx] = updated;
                        widget.editor.setRedactions(list);
                      }
                    },
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(Icons.open_in_full_rounded, size: 10, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DocumentOverlayPainter extends CustomPainter {
  final DocumentPage page;
  final EditorActiveTool activeTool;
  final List<Offset> currentErasePoints;
  final double eraseBrushSize;
  final List<Offset> currentAnnotatePoints;
  final AnnotationType annotateType;
  final Color annotateColor;
  final double annotateStrokeWidth;

  _DocumentOverlayPainter({
    required this.page,
    required this.activeTool,
    required this.currentErasePoints,
    required this.eraseBrushSize,
    required this.currentAnnotatePoints,
    required this.annotateType,
    required this.annotateColor,
    required this.annotateStrokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 1. Erase strokes (rendered as solid white strokes)
    for (final stroke in page.eraseStrokes) {
      _drawStroke(canvas, size, stroke.points, stroke.strokeWidth, Colors.white);
    }
    if (currentErasePoints.isNotEmpty) {
      _drawStroke(canvas, size, currentErasePoints, eraseBrushSize, Colors.white);
    }

    // 2. Annotations
    for (final ann in page.annotations) {
      if (ann.type == AnnotationType.pen) {
        _drawStroke(canvas, size, ann.points, ann.strokeWidth, ann.color);
      } else if (ann.type == AnnotationType.highlighter) {
        _drawStroke(
          canvas,
          size,
          ann.points,
          ann.strokeWidth * 2.5,
          ann.color.withAlpha(90),
        );
      } else if (ann.type == AnnotationType.text && ann.text != null && ann.points.isNotEmpty) {
        final pt = Offset(ann.points.first.dx * w, ann.points.first.dy * h);
        final tp = TextPainter(
          text: TextSpan(
            text: ann.text,
            style: TextStyle(
              color: ann.color,
              fontSize: ann.fontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: w - pt.dx);
        tp.paint(canvas, pt);
      }
    }
    if (currentAnnotatePoints.isNotEmpty) {
      final isHighlighter = annotateType == AnnotationType.highlighter;
      _drawStroke(
        canvas,
        size,
        currentAnnotatePoints,
        isHighlighter ? annotateStrokeWidth * 2.5 : annotateStrokeWidth,
        isHighlighter ? annotateColor.withAlpha(90) : annotateColor,
      );
    }

    // 3. Watermark
    if (page.watermark.enabled && page.watermark.text.isNotEmpty) {
      canvas.save();
      final center = Offset(w / 2, h / 2);
      canvas.translate(center.dx, center.dy);
      final rad = page.watermark.rotation * (math.pi / 180.0);
      canvas.rotate(rad);

      final color = page.watermark.color.withValues(alpha: page.watermark.opacity);
      final tp = TextPainter(
        text: TextSpan(
          text: page.watermark.text,
          style: TextStyle(
            color: color,
            fontSize: page.watermark.fontSize,
            fontWeight: FontWeight.bold,
            letterSpacing: 2.0,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }

    // 4. Redaction rectangles (for non-redact tool view, render static black boxes)
    if (activeTool != EditorActiveTool.redact) {
      final redPaint = Paint()
        ..color = Colors.black
        ..style = PaintingStyle.fill;
      for (final r in page.redactions) {
        final rect = Rect.fromLTWH(r.left * w, r.top * h, r.width * w, r.height * h);
        canvas.drawRect(rect, redPaint);
      }
    }

    // 5. Margin Guide (when margins tool is active or margins exist)
    if (activeTool == EditorActiveTool.margins || page.margins.hasMargins) {
      final m = page.margins;
      final mLeft = (m.left / 100.0) * (w * 0.25);
      final mTop = (m.top / 100.0) * (h * 0.25);
      final mRight = w - ((m.right / 100.0) * (w * 0.25));
      final mBottom = h - ((m.bottom / 100.0) * (h * 0.25));

      final guidePaint = Paint()
        ..color = AppColors.primary.withAlpha(activeTool == EditorActiveTool.margins ? 180 : 80)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;

      // Draw dashed guide box
      _drawDashedRect(canvas, Rect.fromLTRB(mLeft, mTop, mRight, mBottom), guidePaint);
    }

    // 6. Page Border
    if (page.border.enabled && page.border.thickness > 0) {
      final b = page.border;
      final strokeW = b.thickness;
      final borderPaint = Paint()
        ..color = b.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW;

      final inset = strokeW / 2;
      final rect = Rect.fromLTWH(inset, inset, w - strokeW, h - strokeW);

      if (b.style == 'dashed') {
        _drawDashedRect(canvas, rect, borderPaint);
      } else if (b.style == 'double') {
        canvas.drawRect(rect, borderPaint);
        final innerInset = strokeW * 1.5;
        if (w > innerInset * 2 && h > innerInset * 2) {
          canvas.drawRect(
            Rect.fromLTWH(innerInset, innerInset, w - (innerInset * 2), h - (innerInset * 2)),
            borderPaint,
          );
        }
      } else {
        canvas.drawRect(rect, borderPaint);
      }
    }
  }

  void _drawStroke(Canvas canvas, Size size, List<Offset> points, double strokeWidth, Color color) {
    if (points.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    if (points.length == 1) {
      final pt = Offset(points[0].dx * size.width, points[0].dy * size.height);
      canvas.drawCircle(pt, strokeWidth / 2, paint..style = PaintingStyle.fill);
      return;
    }

    final path = Path();
    path.moveTo(points[0].dx * size.width, points[0].dy * size.height);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx * size.width, points[i].dy * size.height);
    }
    canvas.drawPath(path, paint);
  }

  void _drawDashedRect(Canvas canvas, Rect rect, Paint paint) {
    const dashLength = 5.0;
    const dashSpace = 4.0;

    void drawDashedLine(Offset start, Offset end) {
      final distance = (end - start).distance;
      final unit = (end - start) / distance;
      double current = 0.0;
      while (current < distance) {
        final drawLen = math.min(dashLength, distance - current);
        final p1 = start + (unit * current);
        final p2 = p1 + (unit * drawLen);
        canvas.drawLine(p1, p2, paint);
        current += dashLength + dashSpace;
      }
    }

    drawDashedLine(rect.topLeft, rect.topRight);
    drawDashedLine(rect.topRight, rect.bottomRight);
    drawDashedLine(rect.bottomRight, rect.bottomLeft);
    drawDashedLine(rect.bottomLeft, rect.topLeft);
  }

  @override
  bool shouldRepaint(covariant _DocumentOverlayPainter oldDelegate) => true;
}

