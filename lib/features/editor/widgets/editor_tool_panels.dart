import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/providers/editor_provider.dart';
import '../../../core/widgets/document_thumbnail.dart';
import '../../../models/models.dart';

/// Top drawer container for editor tools with title and close button.
Widget buildToolDrawerHeader({
  required BuildContext context,
  required String title,
  required VoidCallback onClose,
  Widget? action,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        title.toUpperCase(),
        style: AppTypography.badge.copyWith(
          color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
          letterSpacing: 1.0,
          fontWeight: FontWeight.bold,
        ),
      ),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ?action,
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: onClose,
            tooltip: 'Close',
          ),
        ],
      ),
    ],
  );
}

/// Helper button for "Apply to All Pages" - restricted exclusively to the 7 permitted tools.
Widget buildApplyToAllButton({
  required BuildContext context,
  required VoidCallback onApply,
  required String toolName,
  required int totalPages,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return OutlinedButton.icon(
    style: OutlinedButton.styleFrom(
      foregroundColor: isDark ? AppColors.darkPrimary : AppColors.primary,
      side: BorderSide(
        color: isDark ? AppColors.darkPrimary.withAlpha(120) : AppColors.primary.withAlpha(120),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      visualDensity: VisualDensity.compact,
    ),
    icon: const Icon(Icons.copy_all_rounded, size: 14),
    label: Text(
      'Apply to All ($totalPages)',
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
    ),
    onPressed: () {
      onApply();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Applied $toolName to all $totalPages pages'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    },
  );
}

// =============================================================================
// 2. ROTATE PANEL (Apply to All supported)
// =============================================================================
class RotateToolPanel extends StatelessWidget {
  final EditorProvider editor;
  const RotateToolPanel({super.key, required this.editor});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalPages = editor.pages.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        border: Border(
          top: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.border),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          buildToolDrawerHeader(
            context: context,
            title: 'Rotate Page',
            onClose: () => editor.setActiveTool(EditorActiveTool.none),
            action: totalPages > 1
                ? buildApplyToAllButton(
                    context: context,
                    toolName: 'Rotation',
                    totalPages: totalPages,
                    onApply: () => editor.applyRotateToAll(90),
                  )
                : null,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildRotateBtn(
                icon: Icons.rotate_left_rounded,
                label: '90° CCW',
                isDark: isDark,
                onTap: () => editor.rotateCurrentPage(clockwise: false),
              ),
              _buildRotateBtn(
                icon: Icons.rotate_right_rounded,
                label: '90° CW',
                isDark: isDark,
                onTap: () => editor.rotateCurrentPage(clockwise: true),
              ),
              _buildRotateBtn(
                icon: Icons.screen_rotation_rounded,
                label: '180°',
                isDark: isDark,
                onTap: () => editor.rotatePageAt(editor.currentPageIndex, deltaDegrees: 180),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRotateBtn({
    required IconData icon,
    required String label,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF262C34) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, size: 22, color: isDark ? AppColors.darkText : AppColors.textPrimary),
            const SizedBox(height: 4),
            Text(label, style: AppTypography.badge),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// 3. FILTER PANEL (Apply to All supported)
// =============================================================================
class FilterToolPanel extends StatelessWidget {
  final EditorProvider editor;
  const FilterToolPanel({super.key, required this.editor});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalPages = editor.pages.length;
    final currentFilter = editor.currentPage?.filterType.toLowerCase() ?? 'auto';

    final filters = [
      {'id': 'original', 'name': 'Original'},
      {'id': 'auto', 'name': 'Auto-Color'},
      {'id': 'light_text', 'name': 'Light Text'},
      {'id': 'grayscale', 'name': 'Grayscale'},
      {'id': 'whiteboard', 'name': 'Whiteboard'},
      {'id': 'bw', 'name': 'B&W'},
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        border: Border(
          top: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.border),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          buildToolDrawerHeader(
            context: context,
            title: 'Document Filters',
            onClose: () => editor.setActiveTool(EditorActiveTool.none),
            action: totalPages > 1
                ? buildApplyToAllButton(
                    context: context,
                    toolName: 'Filter ($currentFilter)',
                    totalPages: totalPages,
                    onApply: () => editor.applyFilterToAll(currentFilter),
                  )
                : null,
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: filters.map((f) {
                final isSelected = currentFilter == f['id'] ||
                    (f['id'] == 'auto' && (currentFilter == 'auto' || currentFilter == 'color'));
                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: InkWell(
                    onTap: () => editor.setFilter(f['id']!),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? (isDark ? AppColors.darkPrimary : AppColors.primary)
                            : (isDark ? const Color(0xFF262C34) : const Color(0xFFF1F5F9)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        f['name']!,
                        style: AppTypography.buttonSmall.copyWith(
                          color: isSelected
                              ? (isDark ? const Color(0xFF0F172A) : Colors.white)
                              : (isDark ? AppColors.darkText : AppColors.textPrimary),
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// 4. ADJUST PANEL (7 sliders, reset, Apply to All supported)
// =============================================================================
class AdjustToolPanel extends StatefulWidget {
  final EditorProvider editor;
  const AdjustToolPanel({super.key, required this.editor});

  @override
  State<AdjustToolPanel> createState() => _AdjustToolPanelState();
}

class _AdjustToolPanelState extends State<AdjustToolPanel> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final page = widget.editor.currentPage;
    final totalPages = widget.editor.pages.length;

    final brightness = page?.brightness ?? 0.0;
    final contrast = page?.contrast ?? 0.0;
    final sharpness = page?.sharpness ?? 0.0;
    final highlights = page?.highlights ?? 0.0;
    final shadows = page?.shadows ?? 0.0;
    final exposure = page?.exposure ?? 0.0;
    final saturation = page?.saturation ?? 0.0;

    return Container(
      constraints: const BoxConstraints(maxHeight: 280),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        border: Border(
          top: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.border),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          buildToolDrawerHeader(
            context: context,
            title: 'Adjustments',
            onClose: () => widget.editor.setActiveTool(EditorActiveTool.none),
            action: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: widget.editor.resetAllAdjustments,
                  child: const Text('Reset All', style: TextStyle(fontSize: 11)),
                ),
                if (totalPages > 1) ...[
                  const SizedBox(width: 4),
                  buildApplyToAllButton(
                    context: context,
                    toolName: 'Adjustments',
                    totalPages: totalPages,
                    onApply: widget.editor.applyAdjustmentsToAll,
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              children: [
                _buildSliderRow(
                  label: 'Brightness',
                  icon: Icons.brightness_6_rounded,
                  value: brightness,
                  min: -0.5,
                  max: 0.5,
                  isDark: isDark,
                  onChanged: (v) => widget.editor.setAdjustments(brightness: v),
                  onReset: () => widget.editor.resetIndividualAdjustment('brightness'),
                ),
                _buildSliderRow(
                  label: 'Contrast',
                  icon: Icons.contrast_rounded,
                  value: contrast,
                  min: -0.5,
                  max: 0.5,
                  isDark: isDark,
                  onChanged: (v) => widget.editor.setAdjustments(contrast: v),
                  onReset: () => widget.editor.resetIndividualAdjustment('contrast'),
                ),
                _buildSliderRow(
                  label: 'Sharpness',
                  icon: Icons.details_rounded,
                  value: sharpness,
                  min: 0.0,
                  max: 1.0,
                  isDark: isDark,
                  onChanged: (v) => widget.editor.setAdjustments(sharpness: v),
                  onReset: () => widget.editor.resetIndividualAdjustment('sharpness'),
                ),
                _buildSliderRow(
                  label: 'Highlights',
                  icon: Icons.highlight_rounded,
                  value: highlights,
                  min: -0.5,
                  max: 0.5,
                  isDark: isDark,
                  onChanged: (v) => widget.editor.setAdjustments(highlights: v),
                  onReset: () => widget.editor.resetIndividualAdjustment('highlights'),
                ),
                _buildSliderRow(
                  label: 'Shadows',
                  icon: Icons.wb_shade_rounded,
                  value: shadows,
                  min: -0.5,
                  max: 0.5,
                  isDark: isDark,
                  onChanged: (v) => widget.editor.setAdjustments(shadows: v),
                  onReset: () => widget.editor.resetIndividualAdjustment('shadows'),
                ),
                _buildSliderRow(
                  label: 'Exposure',
                  icon: Icons.exposure_rounded,
                  value: exposure,
                  min: -0.5,
                  max: 0.5,
                  isDark: isDark,
                  onChanged: (v) => widget.editor.setAdjustments(exposure: v),
                  onReset: () => widget.editor.resetIndividualAdjustment('exposure'),
                ),
                _buildSliderRow(
                  label: 'Saturation',
                  icon: Icons.color_lens_rounded,
                  value: saturation,
                  min: -0.5,
                  max: 0.5,
                  isDark: isDark,
                  onChanged: (v) => widget.editor.setAdjustments(saturation: v),
                  onReset: () => widget.editor.resetIndividualAdjustment('saturation'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderRow({
    required String label,
    required IconData icon,
    required double value,
    required double min,
    required double max,
    required bool isDark,
    required ValueChanged<double> onChanged,
    required VoidCallback onReset,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary),
          const SizedBox(width: 6),
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.darkText : AppColors.textPrimary,
              ),
            ),
          ),
          Expanded(
            child: Slider(
              value: value,
              min: min,
              max: max,
              activeColor: isDark ? AppColors.darkPrimary : AppColors.primary,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 38,
            child: Text(
              '${(value * 100).toInt()}%',
              style: AppTypography.badge.copyWith(fontSize: 10),
              textAlign: TextAlign.end,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.restart_alt_rounded, size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28),
            onPressed: onReset,
            tooltip: 'Reset $label',
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// 6. ERASE PANEL (No Apply to All)
// =============================================================================
class EraseToolPanel extends StatelessWidget {
  final EditorProvider editor;
  final double brushSize;
  final ValueChanged<double> onBrushSizeChanged;

  const EraseToolPanel({
    super.key,
    required this.editor,
    required this.brushSize,
    required this.onBrushSizeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        border: Border(
          top: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.border),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          buildToolDrawerHeader(
            context: context,
            title: 'Erase Brush',
            onClose: () => editor.setActiveTool(EditorActiveTool.none),
            action: TextButton(
              onPressed: editor.clearEraseStrokes,
              child: const Text('Clear All', style: TextStyle(color: AppColors.error, fontSize: 12)),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.brush_rounded, size: 16),
              const SizedBox(width: 8),
              const Text('Brush Size:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              Expanded(
                child: Slider(
                  value: brushSize,
                  min: 5.0,
                  max: 50.0,
                  activeColor: isDark ? AppColors.darkPrimary : AppColors.primary,
                  onChanged: onBrushSizeChanged,
                ),
              ),
              Text('${brushSize.toInt()}px', style: AppTypography.badge),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'Drag across the document to white-out unwanted marks or text.',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// 7. ANNOTATE PANEL (No Apply to All)
// =============================================================================
class AnnotateToolPanel extends StatelessWidget {
  final EditorProvider editor;
  final AnnotationType activeType;
  final Color activeColor;
  final double strokeWidth;
  final ValueChanged<AnnotationType> onTypeChanged;
  final ValueChanged<Color> onColorChanged;
  final ValueChanged<double> onStrokeWidthChanged;
  final VoidCallback onAddText;
  final VoidCallback onAddSignature;

  const AnnotateToolPanel({
    super.key,
    required this.editor,
    required this.activeType,
    required this.activeColor,
    required this.strokeWidth,
    required this.onTypeChanged,
    required this.onColorChanged,
    required this.onStrokeWidthChanged,
    required this.onAddText,
    required this.onAddSignature,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorPresets = [
      Colors.red,
      Colors.blue,
      Colors.green,
      Colors.amber,
      Colors.black,
      Colors.white,
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        border: Border(
          top: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.border),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          buildToolDrawerHeader(
            context: context,
            title: 'Annotate',
            onClose: () => editor.setActiveTool(EditorActiveTool.none),
            action: TextButton(
              onPressed: editor.clearAnnotations,
              child: const Text('Clear All', style: TextStyle(color: AppColors.error, fontSize: 12)),
            ),
          ),
          const SizedBox(height: 6),
          // Sub-tool selector: Pen, Highlighter, Text, Signature
          Row(
            children: [
              _buildTypeChip('Pen', AnnotationType.pen, Icons.edit_rounded, isDark),
              const SizedBox(width: 8),
              _buildTypeChip('Highlighter', AnnotationType.highlighter, Icons.format_paint_rounded, isDark),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.text_fields_rounded, size: 14),
                label: const Text('Text', style: TextStyle(fontSize: 11)),
                onPressed: onAddText,
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.gesture_rounded, size: 14),
                label: const Text('Sign', style: TextStyle(fontSize: 11)),
                onPressed: onAddSignature,
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Color & Stroke controls
          Row(
            children: [
              for (final c in colorPresets)
                GestureDetector(
                  onTap: () => onColorChanged(c),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: activeColor == c ? AppColors.primary : Colors.grey,
                        width: activeColor == c ? 2.5 : 1,
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              const Text('Size:', style: TextStyle(fontSize: 11)),
              SizedBox(
                width: 90,
                child: Slider(
                  value: strokeWidth,
                  min: 1.0,
                  max: 12.0,
                  activeColor: isDark ? AppColors.darkPrimary : AppColors.primary,
                  onChanged: onStrokeWidthChanged,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTypeChip(String label, AnnotationType type, IconData icon, bool isDark) {
    final isSelected = activeType == type;
    return InkWell(
      onTap: () => onTypeChanged(type),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? AppColors.darkPrimary : AppColors.primary)
              : (isDark ? const Color(0xFF262C34) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? Colors.white : (isDark ? AppColors.darkText : AppColors.textPrimary),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.white : (isDark ? AppColors.darkText : AppColors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// 8. WATERMARK PANEL (Apply to All supported)
// =============================================================================
class WatermarkToolPanel extends StatefulWidget {
  final EditorProvider editor;
  const WatermarkToolPanel({super.key, required this.editor});

  @override
  State<WatermarkToolPanel> createState() => _WatermarkToolPanelState();
}

class _WatermarkToolPanelState extends State<WatermarkToolPanel> {
  late TextEditingController _textCtrl;

  @override
  void initState() {
    super.initState();
    final currentText = widget.editor.currentPage?.watermark.text ?? 'CONFIDENTIAL';
    _textCtrl = TextEditingController(text: currentText);
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final wm = widget.editor.currentPage?.watermark ?? const WatermarkConfig();
    final totalPages = widget.editor.pages.length;

    final presets = ['CONFIDENTIAL', 'DRAFT', 'COPY', 'ORIGINAL', 'SAMPLE'];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        border: Border(
          top: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.border),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          buildToolDrawerHeader(
            context: context,
            title: 'Watermark',
            onClose: () => widget.editor.setActiveTool(EditorActiveTool.none),
            action: totalPages > 1
                ? buildApplyToAllButton(
                    context: context,
                    toolName: 'Watermark',
                    totalPages: totalPages,
                    onApply: () => widget.editor.applyWatermarkToAll(wm),
                  )
                : null,
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _textCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Watermark Text',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  ),
                  onChanged: (val) {
                    widget.editor.updateWatermark(wm.copyWith(text: val, enabled: true));
                  },
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                value: wm.enabled,
                activeThumbColor: isDark ? AppColors.darkPrimary : AppColors.primary,
                onChanged: (v) {
                  widget.editor.updateWatermark(wm.copyWith(enabled: v));
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Preset chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: presets.map((p) {
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    label: Text(p, style: const TextStyle(fontSize: 10)),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      _textCtrl.text = p;
                      widget.editor.updateWatermark(wm.copyWith(text: p, enabled: true));
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Text('Opacity:', style: TextStyle(fontSize: 11)),
              Expanded(
                child: Slider(
                  value: wm.opacity,
                  min: 0.1,
                  max: 1.0,
                  activeColor: isDark ? AppColors.darkPrimary : AppColors.primary,
                  onChanged: (v) => widget.editor.updateWatermark(wm.copyWith(opacity: v)),
                ),
              ),
              const Text('Angle:', style: TextStyle(fontSize: 11)),
              Expanded(
                child: Slider(
                  value: wm.rotation,
                  min: -90.0,
                  max: 90.0,
                  activeColor: isDark ? AppColors.darkPrimary : AppColors.primary,
                  onChanged: (v) => widget.editor.updateWatermark(wm.copyWith(rotation: v)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// 9. REDACT PANEL (Genuine destructive warning badge, No Apply to All)
// =============================================================================
class RedactToolPanel extends StatelessWidget {
  final EditorProvider editor;
  const RedactToolPanel({super.key, required this.editor});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final redactions = editor.currentPage?.redactions ?? [];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        border: Border(
          top: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.border),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          buildToolDrawerHeader(
            context: context,
            title: 'Redaction (${redactions.length})',
            onClose: () => editor.setActiveTool(EditorActiveTool.none),
            action: redactions.isNotEmpty
                ? TextButton(
                    onPressed: editor.clearRedactions,
                    child: const Text('Clear All', style: TextStyle(color: AppColors.error, fontSize: 12)),
                  )
                : null,
          ),
          const SizedBox(height: 8),
          // Prominent Warning / Info Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.error.withAlpha(20),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.error.withAlpha(80)),
            ),
            child: Row(
              children: [
                const Icon(Icons.security_rounded, size: 16, color: AppColors.error),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Genuine Redaction: Redacted areas permanently destroy underlying text and pixels upon export.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark ? AppColors.darkPrimary : AppColors.primary,
                foregroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
              ),
              icon: const Icon(Icons.add_box_rounded, size: 18),
              label: const Text('Add Redaction Box'),
              onPressed: () {
                // Place a default box in center of page
                final id = 'redact_${DateTime.now().microsecondsSinceEpoch}';
                editor.addRedaction(
                  RedactionRect(id: id, left: 0.25, top: 0.40, width: 0.50, height: 0.10),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// 10. RESIZE PANEL (Apply to All supported)
// =============================================================================
class ResizeToolPanel extends StatelessWidget {
  final EditorProvider editor;
  const ResizeToolPanel({super.key, required this.editor});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalPages = editor.pages.length;
    final currentPreset = editor.currentPage?.resize.preset ?? 'original';

    final presets = [
      {'id': 'original', 'name': 'Original'},
      {'id': 'a4', 'name': 'A4 (210×297)'},
      {'id': 'a5', 'name': 'A5 (148×210)'},
      {'id': 'letter', 'name': 'US Letter'},
      {'id': 'legal', 'name': 'US Legal'},
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        border: Border(
          top: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.border),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          buildToolDrawerHeader(
            context: context,
            title: 'Page Size / Resize',
            onClose: () => editor.setActiveTool(EditorActiveTool.none),
            action: totalPages > 1
                ? buildApplyToAllButton(
                    context: context,
                    toolName: 'Resize ($currentPreset)',
                    totalPages: totalPages,
                    onApply: () => editor.applyResizeToAll(PageResizeConfig(preset: currentPreset)),
                  )
                : null,
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: presets.map((p) {
                final isSelected = currentPreset == p['id'];
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    onTap: () => editor.updateResize(PageResizeConfig(preset: p['id']!)),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? (isDark ? AppColors.darkPrimary : AppColors.primary)
                            : (isDark ? const Color(0xFF262C34) : const Color(0xFFF1F5F9)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        p['name']!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected
                              ? (isDark ? const Color(0xFF0F172A) : Colors.white)
                              : (isDark ? AppColors.darkText : AppColors.textPrimary),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// 11. MARGINS PANEL (Apply to All supported)
// =============================================================================
class MarginsToolPanel extends StatefulWidget {
  final EditorProvider editor;
  const MarginsToolPanel({super.key, required this.editor});

  @override
  State<MarginsToolPanel> createState() => _MarginsToolPanelState();
}

class _MarginsToolPanelState extends State<MarginsToolPanel> {
  bool _isUniform = true;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final margins = widget.editor.currentPage?.margins ?? const PageMargins();
    final totalPages = widget.editor.pages.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        border: Border(
          top: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.border),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          buildToolDrawerHeader(
            context: context,
            title: 'Page Margins',
            onClose: () => widget.editor.setActiveTool(EditorActiveTool.none),
            action: totalPages > 1
                ? buildApplyToAllButton(
                    context: context,
                    toolName: 'Margins',
                    totalPages: totalPages,
                    onApply: () => widget.editor.applyMarginsToAll(margins),
                  )
                : null,
          ),
          Row(
            children: [
              const Text('Uniform Margins:', style: TextStyle(fontSize: 12)),
              const Spacer(),
              Switch(
                value: _isUniform,
                activeThumbColor: isDark ? AppColors.darkPrimary : AppColors.primary,
                onChanged: (val) => setState(() => _isUniform = val),
              ),
              TextButton(
                onPressed: () => widget.editor.updateMargins(const PageMargins()),
                child: const Text('Reset', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
          if (_isUniform) ...[
            Row(
              children: [
                const Text('All Margins:', style: TextStyle(fontSize: 11)),
                Expanded(
                  child: Slider(
                    value: margins.top,
                    min: 0.0,
                    max: 80.0,
                    activeColor: isDark ? AppColors.darkPrimary : AppColors.primary,
                    onChanged: (v) {
                      widget.editor.updateMargins(PageMargins(top: v, bottom: v, left: v, right: v));
                    },
                  ),
                ),
                Text('${margins.top.toInt()}pt', style: AppTypography.badge),
              ],
            ),
          ] else ...[
            Row(
              children: [
                const SizedBox(width: 44, child: Text('Top:', style: TextStyle(fontSize: 11))),
                Expanded(
                  child: Slider(
                    value: margins.top,
                    min: 0.0,
                    max: 80.0,
                    activeColor: isDark ? AppColors.darkPrimary : AppColors.primary,
                    onChanged: (v) => widget.editor.updateMargins(margins.copyWith(top: v)),
                  ),
                ),
                const SizedBox(width: 44, child: Text('Bottom:', style: TextStyle(fontSize: 11))),
                Expanded(
                  child: Slider(
                    value: margins.bottom,
                    min: 0.0,
                    max: 80.0,
                    activeColor: isDark ? AppColors.darkPrimary : AppColors.primary,
                    onChanged: (v) => widget.editor.updateMargins(margins.copyWith(bottom: v)),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                const SizedBox(width: 44, child: Text('Left:', style: TextStyle(fontSize: 11))),
                Expanded(
                  child: Slider(
                    value: margins.left,
                    min: 0.0,
                    max: 80.0,
                    activeColor: isDark ? AppColors.darkPrimary : AppColors.primary,
                    onChanged: (v) => widget.editor.updateMargins(margins.copyWith(left: v)),
                  ),
                ),
                const SizedBox(width: 44, child: Text('Right:', style: TextStyle(fontSize: 11))),
                Expanded(
                  child: Slider(
                    value: margins.right,
                    min: 0.0,
                    max: 80.0,
                    activeColor: isDark ? AppColors.darkPrimary : AppColors.primary,
                    onChanged: (v) => widget.editor.updateMargins(margins.copyWith(right: v)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// 12. BORDER PANEL (Apply to All supported)
// =============================================================================
class BorderToolPanel extends StatelessWidget {
  final EditorProvider editor;
  const BorderToolPanel({super.key, required this.editor});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = editor.currentPage?.border ?? const PageBorder();
    final totalPages = editor.pages.length;

    final styles = ['solid', 'dashed', 'double'];
    final colorPresets = [
      Colors.black,
      Colors.grey,
      Colors.white,
      AppColors.primary,
      Colors.red,
      Colors.amber,
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        border: Border(
          top: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.border),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          buildToolDrawerHeader(
            context: context,
            title: 'Page Border',
            onClose: () => editor.setActiveTool(EditorActiveTool.none),
            action: totalPages > 1
                ? buildApplyToAllButton(
                    context: context,
                    toolName: 'Border',
                    totalPages: totalPages,
                    onApply: () => editor.applyBorderToAll(border),
                  )
                : null,
          ),
          Row(
            children: [
              const Text('Enable Border:', style: TextStyle(fontSize: 12)),
              const Spacer(),
              Switch(
                value: border.enabled,
                activeThumbColor: isDark ? AppColors.darkPrimary : AppColors.primary,
                onChanged: (v) => editor.updateBorder(border.copyWith(enabled: v)),
              ),
            ],
          ),
          if (border.enabled) ...[
            Row(
              children: [
                const Text('Thickness:', style: TextStyle(fontSize: 11)),
                Expanded(
                  child: Slider(
                    value: border.thickness,
                    min: 1.0,
                    max: 12.0,
                    activeColor: isDark ? AppColors.darkPrimary : AppColors.primary,
                    onChanged: (v) => editor.updateBorder(border.copyWith(thickness: v)),
                  ),
                ),
                Text('${border.thickness.toInt()}pt', style: AppTypography.badge),
              ],
            ),
            Row(
              children: [
                const Text('Style: ', style: TextStyle(fontSize: 11)),
                for (final s in styles)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(s.toUpperCase(), style: const TextStyle(fontSize: 10)),
                      selected: border.style == s,
                      visualDensity: VisualDensity.compact,
                      onSelected: (sel) {
                        if (sel) editor.updateBorder(border.copyWith(style: s));
                      },
                    ),
                  ),
                const Spacer(),
                for (final c in colorPresets)
                  GestureDetector(
                    onTap: () => editor.updateBorder(border.copyWith(colorValue: c.toARGB32())),
                    child: Container(
                      margin: const EdgeInsets.only(left: 4),
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: border.colorValue == c.toARGB32() ? AppColors.primary : Colors.grey,
                          width: border.colorValue == c.toARGB32() ? 2 : 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// 13. REORDER PANEL (Dynamic page numbers, Done button, No Apply to All)
// =============================================================================
class ReorderToolPanel extends StatelessWidget {
  final EditorProvider editor;
  const ReorderToolPanel({super.key, required this.editor});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      constraints: const BoxConstraints(maxHeight: 280),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        border: Border(
          top: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.border),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          buildToolDrawerHeader(
            context: context,
            title: 'Reorder Pages',
            onClose: () => editor.setActiveTool(EditorActiveTool.none),
            action: FilledButton(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                visualDensity: VisualDensity.compact,
                backgroundColor: isDark ? AppColors.darkPrimary : AppColors.primary,
                foregroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
              ),
              onPressed: () => editor.setActiveTool(EditorActiveTool.none),
              child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Hold and drag any page to change document page sequence.',
            style: TextStyle(
              fontSize: 11,
              color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: editor.pages.length,
              // ignore: deprecated_member_use
              onReorder: editor.reorderPages,
              itemBuilder: (context, index) {
                final page = editor.pages[index];
                return Container(
                  key: ValueKey(page.id),
                  margin: const EdgeInsets.only(right: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 72,
                        height: 100,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: editor.currentPageIndex == index
                                ? (isDark ? AppColors.darkPrimary : AppColors.primary)
                                : (isDark ? AppColors.darkBorder : AppColors.border),
                            width: editor.currentPageIndex == index ? 2.5 : 1,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            DocumentThumbnail(
                              pageCount: 1,
                              width: 68,
                              height: 96,
                              rotationDegrees: page.rotationDegrees,
                              filterType: page.filterType,
                              pageNumber: index + 1,
                              imagePath: page.processedImagePath ?? page.originalImagePath,
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Icon(Icons.drag_indicator_rounded, size: 14, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Page ${index + 1}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppColors.darkText : AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

