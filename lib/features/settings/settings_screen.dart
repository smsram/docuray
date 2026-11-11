import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/routing/app_router.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/setting_tile.dart';
import '../../core/widgets/segmented_control.dart';

/// Screen 13: Complete Settings UI with Account, Cloud, AI, Scanning, Documents,
/// Appearance (working theme switcher), Privacy, and About sections.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            // ─── 1. ACCOUNT ──────────────────────────────────────────
            const SettingsSectionHeader(title: 'Account'),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  SettingTile(
                    icon: Icons.account_circle_outlined,
                    title: settings.isDriveConnected
                        ? (settings.driveUserEmail ?? 'Google Account')
                        : 'Sign in with Google',
                    subtitle: settings.isDriveConnected ? 'Connected' : 'Sync scans across devices',
                    trailing: settings.isDriveConnected
                        ? const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20)
                        : null,
                    onTap: () => context.push(AppRouter.driveSettings),
                  ),
                ],
              ),
            ),

            // ─── 2. CLOUD ────────────────────────────────────────────
            const SettingsSectionHeader(title: 'Cloud & Backup'),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  SettingTile(
                    icon: Icons.cloud_outlined,
                    title: 'Google Drive',
                    subtitle: settings.isDriveConnected ? 'Auto-backup enabled' : 'Not connected',
                    trailing: Text(
                      settings.isDriveConnected ? 'Connected' : 'Setup',
                      style: AppTypography.buttonSmall.copyWith(
                        color: settings.isDriveConnected
                            ? AppColors.success
                            : (isDark ? AppColors.darkPrimary : AppColors.primary),
                      ),
                    ),
                    onTap: () => context.push(AppRouter.driveSettings),
                  ),
                ],
              ),
            ),

            // ─── 3. AI ───────────────────────────────────────────────
            const SettingsSectionHeader(title: 'Intelligence'),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  SettingTile(
                    icon: Icons.auto_awesome_rounded,
                    title: 'AI Assistant',
                    subtitle: 'Powered by Google Gemini',
                    trailing: Text(
                      'Configure',
                      style: AppTypography.buttonSmall.copyWith(
                        color: isDark ? AppColors.darkPrimary : AppColors.primary,
                      ),
                    ),
                    onTap: () => context.push(AppRouter.aiSettings),
                  ),
                ],
              ),
            ),

            // ─── 4. SCANNING ─────────────────────────────────────────
            const SettingsSectionHeader(title: 'Scanning'),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  ToggleSettingTile(
                    icon: Icons.flash_auto_rounded,
                    title: 'Auto Capture',
                    subtitle: 'Automatically take photo when corners detected',
                    value: settings.autoCapture,
                    onChanged: settings.setAutoCapture,
                  ),
                  const Divider(),
                  ToggleSettingTile(
                    icon: Icons.auto_fix_high_rounded,
                    title: 'Auto Enhancement',
                    subtitle: 'Clean paper wrinkles and correct perspective',
                    value: settings.autoEnhancement,
                    onChanged: settings.setAutoEnhancement,
                  ),
                  const Divider(),
                  SettingTile(
                    icon: Icons.crop_free_rounded,
                    title: 'Default Scan Mode',
                    subtitle: settings.defaultScanMode,
                    trailing: Text(
                      settings.defaultScanMode,
                      style: AppTypography.secondaryMedium.copyWith(
                        color: isDark ? AppColors.darkPrimary : AppColors.primary,
                      ),
                    ),
                    onTap: () => _showModePicker(context, settings),
                  ),
                  const Divider(),
                  SettingTile(
                    icon: Icons.filter_b_and_w_rounded,
                    title: 'Default Filter',
                    subtitle: settings.defaultFilter,
                    trailing: Text(
                      settings.defaultFilter,
                      style: AppTypography.secondaryMedium.copyWith(
                        color: isDark ? AppColors.darkPrimary : AppColors.primary,
                      ),
                    ),
                    onTap: () => _showFilterPicker(context, settings),
                  ),
                  const Divider(),
                  SettingTile(
                    icon: Icons.high_quality_rounded,
                    title: 'Scan Quality',
                    subtitle: settings.scanQuality,
                    trailing: Text(
                      settings.scanQuality,
                      style: AppTypography.secondaryMedium.copyWith(
                        color: isDark ? AppColors.darkPrimary : AppColors.primary,
                      ),
                    ),
                    onTap: () => _showQualityPicker(context, settings),
                  ),
                ],
              ),
            ),

            // ─── 5. DOCUMENTS ────────────────────────────────────────
            const SettingsSectionHeader(title: 'Documents & Storage'),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  SettingTile(
                    icon: Icons.picture_as_pdf_outlined,
                    title: 'Default PDF Quality',
                    subtitle: settings.defaultPdfQuality,
                    trailing: Text(
                      settings.defaultPdfQuality,
                      style: AppTypography.secondaryMedium.copyWith(
                        color: isDark ? AppColors.darkPrimary : AppColors.primary,
                      ),
                    ),
                    onTap: () => _showPdfQualityPicker(context, settings),
                  ),
                  const Divider(),
                  SettingTile(
                    icon: Icons.pie_chart_outline_rounded,
                    title: 'Storage',
                    subtitle: '128 MB used · Local storage metrics',
                    onTap: () => context.push(AppRouter.storage),
                  ),
                  const Divider(),
                  SettingTile(
                    icon: Icons.folder_open_rounded,
                    title: 'Folders',
                    subtitle: 'Manage categories and document tags',
                    onTap: () => context.push(AppRouter.folders),
                  ),
                  const Divider(),
                  ToggleSettingTile(
                    icon: Icons.title_rounded,
                    title: 'Auto Naming',
                    subtitle: 'Generate document titles using date & time',
                    value: true,
                    onChanged: (v) {},
                  ),
                ],
              ),
            ),

            // ─── 6. APPEARANCE ───────────────────────────────────────
            const SettingsSectionHeader(title: 'Appearance'),
            AppCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                        size: 22,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                      ),
                      const SizedBox(width: AppDimensions.space16),
                      Text(
                        'Theme',
                        style: AppTypography.bodyMedium.copyWith(
                          color: isDark ? AppColors.darkText : AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedControl<ThemeMode>(
                      items: const {
                        ThemeMode.system: 'System',
                        ThemeMode.light: 'Light',
                        ThemeMode.dark: 'Dark',
                      },
                      selectedValue: settings.themeMode,
                      onValueChanged: (mode) => settings.setThemeMode(mode),
                    ),
                  ),
                ],
              ),
            ),

            // ─── 7. PRIVACY & SECURITY ───────────────────────────────
            const SettingsSectionHeader(title: 'Privacy & Security'),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  ToggleSettingTile(
                    icon: Icons.lock_outline_rounded,
                    title: 'App Lock',
                    subtitle: 'Require authentication when opening DocuRay',
                    value: settings.appLock,
                    onChanged: settings.setAppLock,
                  ),
                  const Divider(),
                  ToggleSettingTile(
                    icon: Icons.fingerprint_rounded,
                    title: 'Biometric Unlock',
                    subtitle: 'Use fingerprint or face recognition',
                    value: settings.biometricLock,
                    enabled: settings.appLock,
                    onChanged: settings.setBiometricLock,
                  ),
                  const Divider(),
                  SettingTile(
                    icon: Icons.shield_outlined,
                    title: 'Permissions',
                    subtitle: 'Camera, Photos, and storage access',
                    onTap: () => context.push(AppRouter.permissions),
                  ),
                ],
              ),
            ),

            // ─── 8. ABOUT ────────────────────────────────────────────
            const SettingsSectionHeader(title: 'About DocuRay'),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  SettingTile(
                    icon: Icons.info_outline_rounded,
                    title: 'About DocuRay',
                    subtitle: 'Version 1.0.0 (Build 1)',
                    onTap: () => context.push(AppRouter.about),
                  ),
                  const Divider(),
                  SettingTile(
                    icon: Icons.source_outlined,
                    title: 'Open Source Licenses',
                    onTap: () => context.push(AppRouter.licenses),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showModePicker(BuildContext context, SettingsProvider settings) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: AppDimensions.borderSheet),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: ['Document', 'ID Card', 'Batch', 'Book'].map((m) {
            return ListTile(
              title: Text(m),
              trailing: settings.defaultScanMode == m ? const Icon(Icons.check, color: AppColors.primary) : null,
              onTap: () {
                settings.setDefaultScanMode(m);
                Navigator.pop(ctx);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showFilterPicker(BuildContext context, SettingsProvider settings) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: AppDimensions.borderSheet),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: ['Auto', 'Original', 'Color', 'Grayscale', 'B&W'].map((f) {
            return ListTile(
              title: Text(f),
              trailing: settings.defaultFilter == f ? const Icon(Icons.check, color: AppColors.primary) : null,
              onTap: () {
                settings.setDefaultFilter(f);
                Navigator.pop(ctx);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showQualityPicker(BuildContext context, SettingsProvider settings) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: AppDimensions.borderSheet),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: ['Standard', 'High', 'Maximum'].map((q) {
            return ListTile(
              title: Text(q),
              trailing: settings.scanQuality == q ? const Icon(Icons.check, color: AppColors.primary) : null,
              onTap: () {
                settings.setScanQuality(q);
                Navigator.pop(ctx);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showPdfQualityPicker(BuildContext context, SettingsProvider settings) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: AppDimensions.borderSheet),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: ['Small', 'Standard', 'High'].map((q) {
            return ListTile(
              title: Text(q),
              trailing: settings.defaultPdfQuality == q ? const Icon(Icons.check, color: AppColors.primary) : null,
              onTap: () {
                settings.setDefaultPdfQuality(q);
                Navigator.pop(ctx);
              },
            );
          }).toList(),
        ),
      ),
    );
  }
}
