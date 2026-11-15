import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
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
                    subtitle: 'Powered by Qwen3-VL-8B (ZeroGPU)',
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
                    title: 'Auto Capture Default',
                    subtitle: 'Automatically take photo when document is steady',
                    value: settings.autoCaptureDefault,
                    onChanged: settings.setAutoCaptureDefault,
                  ),
                  const Divider(),
                  ToggleSettingTile(
                    icon: Icons.crop_rounded,
                    title: 'Auto Crop Default',
                    subtitle: 'Automatically crop to detected document corners',
                    value: settings.autoCropDefault,
                    onChanged: settings.setAutoCropDefault,
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
                    subtitle: 'Local document and cache metrics',
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
                    value: settings.autoNaming,
                    onChanged: settings.setAutoNaming,
                  ),
                ],
              ),
            ),

            // ─── 6. REMEMBER EDITING PREFERENCES ────────────────────
            const SettingsSectionHeader(title: 'Remember Editing Preferences'),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  ToggleSettingTile(
                    icon: Icons.filter_b_and_w_rounded,
                    title: 'Remember Filter',
                    subtitle: 'Apply last-used filter to new scans (Default: Original)',
                    value: settings.rememberFilter,
                    onChanged: settings.setRememberFilter,
                  ),
                  const Divider(),
                  ToggleSettingTile(
                    icon: Icons.tune_rounded,
                    title: 'Remember Adjustments',
                    subtitle: 'Retain custom brightness, contrast, highlights, etc.',
                    value: settings.rememberAdjustments,
                    onChanged: settings.setRememberAdjustments,
                  ),
                  const Divider(),
                  ToggleSettingTile(
                    icon: Icons.aspect_ratio_rounded,
                    title: 'Remember Resize',
                    subtitle: 'Retain chosen paper size (e.g. A4, Letter)',
                    value: settings.rememberResize,
                    onChanged: settings.setRememberResize,
                  ),
                  const Divider(),
                  ToggleSettingTile(
                    icon: Icons.space_dashboard_outlined,
                    title: 'Remember Margins',
                    subtitle: 'Retain custom page margin dimensions',
                    value: settings.rememberMargins,
                    onChanged: settings.setRememberMargins,
                  ),
                  const Divider(),
                  ToggleSettingTile(
                    icon: Icons.border_all_rounded,
                    title: 'Remember Border',
                    subtitle: 'Retain document border configuration',
                    value: settings.rememberBorder,
                    onChanged: settings.setRememberBorder,
                  ),
                  const Divider(),
                  ToggleSettingTile(
                    icon: Icons.branding_watermark_rounded,
                    title: 'Remember Watermark',
                    subtitle: 'Save watermark template (disabled on new scans by default)',
                    value: settings.rememberWatermark,
                    onChanged: settings.setRememberWatermark,
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

            // ─── 7. PRIVACY & PERMISSIONS ───────────────────────────
            const SettingsSectionHeader(title: 'Permissions & Privacy'),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  SettingTile(
                    icon: Icons.shield_outlined,
                    title: 'App Permissions',
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
                  FutureBuilder<PackageInfo>(
                    future: PackageInfo.fromPlatform(),
                    builder: (context, snapshot) {
                      final version = snapshot.data?.version ?? '1.0.0';
                      return SettingTile(
                        icon: Icons.info_outline_rounded,
                        title: 'About DocuRay',
                        subtitle: 'Version $version',
                        onTap: () => context.push(AppRouter.about),
                      );
                    },
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
