import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/setting_tile.dart';
import '../../core/widgets/status_badge.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../models/models.dart';

/// Screen 11: Google Drive Settings with Connected & Disconnected UI states, sync controls,
/// and clear separation from Gemini AI.
class DriveSettingsScreen extends StatelessWidget {
  const DriveSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Google Drive'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: AppDimensions.screenPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Notice explaining Drive is purely for document backup and separate from AI
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? AppColors.darkBorder : const Color(0xFFBFDBFE),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: isDark ? AppColors.darkPrimary : AppColors.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Google Drive backup securely synchronizes your PDFs to your cloud drive. Note: Gemini AI assistant is configured separately.',
                        style: AppTypography.secondary.copyWith(
                          color: isDark ? AppColors.darkText : const Color(0xFF1E3A8A),
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              if (!settings.isDriveConnected)
                _buildDisconnectedState(context, settings, isDark)
              else
                _buildConnectedState(context, settings, isDark),

              const SizedBox(height: 24),

              // Sync Status Preview Visuals
              Text(
                'SYNC STATUS STATES',
                style: AppTypography.badge.copyWith(
                  color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 10),
              AppCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildStatusRow('Synced', StatusBadge.syncStatus(SyncStatus.synced), isDark),
                    const Divider(),
                    _buildStatusRow('Syncing in progress', StatusBadge.syncStatus(SyncStatus.syncing), isDark),
                    const Divider(),
                    _buildStatusRow('Waiting for Wi-Fi', StatusBadge.syncStatus(SyncStatus.waitingForConnection), isDark),
                    const Divider(),
                    _buildStatusRow('Sync failed', StatusBadge.syncStatus(SyncStatus.failed), isDark),
                    const Divider(),
                    _buildStatusRow('Not synced', StatusBadge.syncStatus(SyncStatus.notSynced), isDark),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Disconnected UI State
  Widget _buildDisconnectedState(BuildContext context, SettingsProvider settings, bool isDark) {
    return AppCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF262C34) : const Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.add_to_drive_rounded,
              size: 32,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Google Drive',
            style: AppTypography.sectionTitle.copyWith(
              color: isDark ? AppColors.darkText : AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Back up your scanned documents to Google Drive. Access your PDFs securely from any device.',
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(
              color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          PrimaryButton(
            label: 'Connect Google Drive',
            icon: Icons.cloud_outlined,
            width: double.infinity,
            onPressed: () {
              // Simulate connecting
              settings.connectDrive('user@example.com');
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Connected to Google Drive (Preview).')),
              );
            },
          ),
        ],
      ),
    );
  }

  // Connected UI State
  Widget _buildConnectedState(BuildContext context, SettingsProvider settings, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Connected Account Banner
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: Color(0xFFD1FAE5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded, color: AppColors.success, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      settings.driveUserEmail ?? 'user@gmail.com',
                      style: AppTypography.bodyMedium.copyWith(
                        color: isDark ? AppColors.darkText : AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.cloud_done_rounded, size: 14, color: AppColors.success),
                        const SizedBox(width: 4),
                        Text(
                          'Connected & ready to sync',
                          style: AppTypography.secondary.copyWith(
                            color: AppColors.success,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.logout_rounded, size: 20, color: AppColors.error),
                tooltip: 'Disconnect',
                onPressed: () async {
                  final confirm = await ConfirmDialog.show(
                    context,
                    title: 'Disconnect Google Drive?',
                    message: 'Your local scans will remain safe on your device, but auto-backup will pause.',
                    confirmLabel: 'Disconnect',
                    isDestructive: true,
                  );
                  if (confirm == true) {
                    settings.disconnectDrive();
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Cloud Settings Toggles
        Text(
          'BACKUP SETTINGS',
          style: AppTypography.badge.copyWith(
            color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 10),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              ToggleSettingTile(
                icon: Icons.sync_rounded,
                title: 'Auto Backup',
                subtitle: 'Automatically sync scans when saved',
                value: settings.driveAutoBackup,
                onChanged: settings.setDriveAutoBackup,
              ),
              const Divider(),
              ToggleSettingTile(
                icon: Icons.wifi_rounded,
                title: 'Wi-Fi only',
                subtitle: 'Prevent data usage over cellular connection',
                value: settings.driveWifiOnly,
                onChanged: settings.setDriveWifiOnly,
              ),
              const Divider(),
              SettingTile(
                icon: Icons.folder_outlined,
                title: 'Backup folder',
                subtitle: settings.driveBackupFolder,
                trailing: Text(
                  'Change',
                  style: AppTypography.buttonSmall.copyWith(
                    color: isDark ? AppColors.darkPrimary : AppColors.primary,
                  ),
                ),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Folder selection is a Phase 2 integration.')),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusRow(String label, Widget badge, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTypography.body.copyWith(
              color: isDark ? AppColors.darkText : AppColors.textPrimary,
            ),
          ),
          badge,
        ],
      ),
    );
  }
}
