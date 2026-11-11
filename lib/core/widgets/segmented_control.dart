import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../constants/app_dimensions.dart';

/// Clean segmented control bar with subtle active indicator.
class SegmentedControl<T> extends StatelessWidget {
  final Map<T, String> items;
  final T selectedValue;
  final ValueChanged<T> onValueChanged;
  final double height;
  final bool isExpanded;

  const SegmentedControl({
    super.key,
    required this.items,
    required this.selectedValue,
    required this.onValueChanged,
    this.height = 36.0,
    this.isExpanded = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: height,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(AppDimensions.radiusButton),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.border,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: isExpanded ? MainAxisSize.max : MainAxisSize.min,
        children: items.entries.map((entry) {
          final isSelected = entry.key == selectedValue;

          final segment = GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onValueChanged(entry.key),
            child: AnimatedContainer(
              duration: AppDimensions.durationFast,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected
                    ? (isDark ? AppColors.darkPrimary : Colors.white)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(AppDimensions.radiusButton - 2),
                boxShadow: isSelected && !isDark
                    ? [
                        BoxShadow(
                          color: Colors.black.withAlpha(10),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
              child: Text(
                entry.value,
                style: AppTypography.buttonSmall.copyWith(
                  color: isSelected
                      ? (isDark ? const Color(0xFF0F172A) : AppColors.textPrimary)
                      : (isDark ? AppColors.darkTextSecondary : AppColors.textSecondary),
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          );

          return isExpanded ? Expanded(child: segment) : segment;
        }).toList(),
      ),
    );
  }
}
