import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../constants/app_dimensions.dart';
import '../../models/models.dart';

/// Compact status pill badge.
/// Rule: Pills are appropriate only for compact statuses such as:
/// PDF, 8 pages, Synced, Favorite, etc.
class StatusBadge extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? backgroundColor;
  final Color? textColor;
  final Color? iconColor;

  const StatusBadge({
    super.key,
    required this.label,
    this.icon,
    this.backgroundColor,
    this.textColor,
    this.iconColor,
  });

  factory StatusBadge.pdf({Key? key}) {
    return StatusBadge(
      key: key,
      label: 'PDF',
      backgroundColor: const Color(0xFFFEE2E2),
      textColor: const Color(0xFFDC2626),
    );
  }

  factory StatusBadge.pageCount(int count, {Key? key}) {
    return StatusBadge(
      key: key,
      label: '$count ${count == 1 ? 'page' : 'pages'}',
      backgroundColor: const Color(0xFFF3F4F6),
      textColor: const Color(0xFF4B5563),
    );
  }

  factory StatusBadge.syncStatus(SyncStatus status, {Key? key}) {
    switch (status) {
      case SyncStatus.synced:
        return StatusBadge(
          key: key,
          label: 'Synced',
          icon: Icons.cloud_done_rounded,
          backgroundColor: const Color(0xFFD1FAE5),
          textColor: const Color(0xFF065F46),
          iconColor: const Color(0xFF059669),
        );
      case SyncStatus.syncing:
        return StatusBadge(
          key: key,
          label: 'Syncing',
          icon: Icons.sync_rounded,
          backgroundColor: const Color(0xFFDBEAFE),
          textColor: const Color(0xFF1E40AF),
          iconColor: const Color(0xFF2563EB),
        );
      case SyncStatus.waitingForConnection:
        return StatusBadge(
          key: key,
          label: 'Waiting',
          icon: Icons.cloud_queue_rounded,
          backgroundColor: const Color(0xFFFEF3C7),
          textColor: const Color(0xFF92400E),
          iconColor: const Color(0xFFD97706),
        );
      case SyncStatus.failed:
        return StatusBadge(
          key: key,
          label: 'Sync failed',
          icon: Icons.cloud_off_rounded,
          backgroundColor: const Color(0xFFFEE2E2),
          textColor: const Color(0xFF991B1B),
          iconColor: const Color(0xFFDC2626),
        );
      case SyncStatus.notSynced:
        return StatusBadge(
          key: key,
          label: 'Not synced',
          icon: Icons.cloud_outlined,
          backgroundColor: const Color(0xFFF3F4F6),
          textColor: const Color(0xFF6B7280),
          iconColor: const Color(0xFF9CA3AF),
        );
    }
  }

  factory StatusBadge.favorite({Key? key}) {
    return StatusBadge(
      key: key,
      label: 'Favorite',
      icon: Icons.star_rounded,
      backgroundColor: const Color(0xFFFEF3C7),
      textColor: const Color(0xFF92400E),
      iconColor: const Color(0xFFF59E0B),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bg = isDark
        ? (backgroundColor != null ? backgroundColor!.withAlpha(40) : AppColors.darkBorder)
        : (backgroundColor ?? const Color(0xFFF3F4F6));

    final fg = isDark
        ? (textColor != null ? textColor!.withAlpha(240) : AppColors.darkTextSecondary)
        : (textColor ?? AppColors.textSecondary);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppDimensions.borderPill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: iconColor ?? fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: AppTypography.badge.copyWith(color: fg),
          ),
        ],
      ),
    );
  }
}
