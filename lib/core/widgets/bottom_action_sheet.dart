import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../constants/app_dimensions.dart';

/// Item definition for BottomActionSheet.
class ActionSheetItem {
  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool isDestructive;
  final Color? iconColor;

  const ActionSheetItem({
    required this.title,
    this.subtitle,
    required this.icon,
    required this.onTap,
    this.isDestructive = false,
    this.iconColor,
  });
}

/// Polished bottom sheet with 24px top radius, drag bar, title, and action list.
class BottomActionSheet extends StatelessWidget {
  final String? title;
  final List<ActionSheetItem> items;

  const BottomActionSheet({
    super.key,
    this.title,
    required this.items,
  });

  static Future<T?> show<T>({
    required BuildContext context,
    String? title,
    required List<ActionSheetItem> items,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BottomActionSheet(
        title: title,
        items: items,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: AppDimensions.borderSheet,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 80 : 30),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkBorder : const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              if (title != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      title!,
                      style: AppTypography.subsectionTitle.copyWith(
                        color: isDark ? AppColors.darkText : AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const Divider(),
              ],
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: items.length,
                  separatorBuilder: (context, index) => Divider(
                    height: 1,
                    color: isDark ? AppColors.darkBorder.withAlpha(60) : AppColors.border.withAlpha(80),
                  ),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final color = item.isDestructive
                        ? AppColors.error
                        : (isDark ? AppColors.darkText : AppColors.textPrimary);
                    final iconColor = item.isDestructive
                        ? AppColors.error
                        : (item.iconColor ?? (isDark ? AppColors.darkTextSecondary : AppColors.textSecondary));

                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      leading: Icon(item.icon, color: iconColor, size: 22),
                      title: Text(
                        item.title,
                        style: AppTypography.bodyMedium.copyWith(
                          color: color,
                          fontWeight: item.isDestructive ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                      subtitle: item.subtitle != null
                          ? Text(
                              item.subtitle!,
                              style: AppTypography.secondary.copyWith(
                                color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                              ),
                            )
                          : null,
                      onTap: () {
                        Navigator.of(context).pop();
                        item.onTap();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
