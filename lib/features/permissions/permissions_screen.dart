import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_buttons.dart';

/// Screen 18: Permissions Status Screen describing Camera, Storage, and Notification access.
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  bool _cameraAllowed = true;
  bool _photosAllowed = true;
  bool _notificationsAllowed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('App Permissions'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: AppDimensions.screenPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DocuRay requires specific device permissions to capture high-definition scans and store PDFs on your phone.',
                style: AppTypography.body.copyWith(
                  color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),

              // 1. Camera Permission Card
              _buildPermissionCard(
                icon: Icons.camera_alt_outlined,
                title: 'Camera',
                reason: 'Required to scan physical papers, receipts, and book pages with real-time corner detection.',
                isAllowed: _cameraAllowed,
                onToggle: () => setState(() => _cameraAllowed = !_cameraAllowed),
                isDark: isDark,
              ),
              const SizedBox(height: 16),

              // 2. Photos & Storage Card
              _buildPermissionCard(
                icon: Icons.photo_library_outlined,
                title: 'Photos & Files',
                reason: 'Required to import existing images or PDF documents and save exported files to your device storage.',
                isAllowed: _photosAllowed,
                onToggle: () => setState(() => _photosAllowed = !_photosAllowed),
                isDark: isDark,
              ),
              const SizedBox(height: 16),

              // 3. Notifications Card
              _buildPermissionCard(
                icon: Icons.notifications_none_rounded,
                title: 'Notifications',
                reason: 'Optional notifications when background cloud sync to Google Drive completes or needs attention.',
                isAllowed: _notificationsAllowed,
                onToggle: () => setState(() => _notificationsAllowed = !_notificationsAllowed),
                isDark: isDark,
              ),
              const SizedBox(height: 28),

              // Open Android System Settings CTA
              SecondaryButton(
                label: 'Open Android App Settings',
                icon: Icons.settings_outlined,
                width: double.infinity,
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Opens device system settings in production.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionCard({
    required IconData icon,
    required String title,
    required String reason,
    required bool isAllowed,
    required VoidCallback onToggle,
    required bool isDark,
  }) {
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isAllowed
                      ? AppColors.success.withAlpha(20)
                      : (isDark ? const Color(0xFF262C34) : const Color(0xFFF1F5F9)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 24,
                  color: isAllowed ? AppColors.success : (isDark ? AppColors.darkTextSecondary : AppColors.textSecondary),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.subsectionTitle.copyWith(
                        color: isDark ? AppColors.darkText : AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          isAllowed ? Icons.check_circle_rounded : Icons.cancel_rounded,
                          size: 14,
                          color: isAllowed ? AppColors.success : AppColors.error,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isAllowed ? 'Allowed' : 'Not allowed',
                          style: AppTypography.caption.copyWith(
                            color: isAllowed ? AppColors.success : AppColors.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onToggle,
                child: Text(
                  isAllowed ? 'Revoke' : 'Allow',
                  style: TextStyle(
                    color: isAllowed ? AppColors.error : (isDark ? AppColors.darkPrimary : AppColors.primary),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            reason,
            style: AppTypography.secondary.copyWith(
              color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
