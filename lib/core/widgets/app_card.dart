import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../constants/app_dimensions.dart';

/// Clean card container with 16px radius, subtle border, and optional tap behavior.
class AppCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;
  final Color? borderColor;
  final double? width;
  final double? height;
  final bool isSelected;

  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.all(AppDimensions.space16),
    this.backgroundColor,
    this.borderColor,
    this.width,
    this.height,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bg = backgroundColor ?? (isDark ? AppColors.darkSurface : AppColors.surface);
    final border = isSelected
        ? (isDark ? AppColors.darkPrimary : AppColors.primary)
        : (borderColor ?? (isDark ? AppColors.darkBorder : AppColors.border));

    final card = Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppDimensions.borderCard,
        border: Border.all(
          color: border,
          width: isSelected ? 2.0 : 1.0,
        ),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withAlpha(8),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: child,
    );

    if (onTap != null || onLongPress != null) {
      return Material(
        color: Colors.transparent,
        borderRadius: AppDimensions.borderCard,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: AppDimensions.borderCard,
          child: card,
        ),
      );
    }

    return card;
  }
}
