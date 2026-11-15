import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/providers/documents_provider.dart';
import '../../core/services/google_drive_service.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/app_buttons.dart';
import '../../core/widgets/setting_tile.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../models/models.dart';

/// Screen 11: Real Google Drive Settings with OAuth Sign-In, Back Up Now,
/// Selective Restore with Conflict Resolution, Wi-Fi checks, and Real Sync Dashboard.
class DriveSettingsScreen extends StatefulWidget {
  const DriveSettingsScreen({super.key});

  @override
  State<DriveSettingsScreen> createState() => _DriveSettingsScreenState();
}

class _DriveSettingsScreenState extends State<DriveSettingsScreen> {
  bool _isSigningIn = false;
  bool _isBackingUp = false;
  double _backupProgress = 0.0;
  String _backupStatusMessage = '';

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(String? isoString) {
    if (isoString == null || isoString.isEmpty) return 'Never';
    try {
      final dt = DateTime.parse(isoString);
      return DateFormat('MMM d, y · h:mm a').format(dt.toLocal());
    } catch (_) {
      return isoString;
    }
  }

  Future<void> _handleSignIn(SettingsProvider settings) async {
    setState(() => _isSigningIn = true);
    try {
      final success = await settings.signInGoogleDrive();
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connected to Google Drive as ${settings.driveUserEmail}'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Google Sign-In failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSigningIn = false);
    }
  }

  Future<void> _handleDisconnect(SettingsProvider settings) async {
    final confirm = await ConfirmDialog.show(
      context,
      title: 'Disconnect Google Drive?',
      message: 'Your local documents will remain safe on your device, but cloud synchronization will pause.',
      confirmLabel: 'Disconnect',
      isDestructive: true,
    );

    if (confirm == true) {
      await settings.disconnectGoogleDrive();
      // If auto-backup was enabled, turn it off since Drive is disconnected
      if (settings.driveAutoBackup) {
        await settings.setDriveAutoBackup(false);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Disconnected from Google Drive.')),
        );
      }
    }
  }

  Future<void> _handleBackupNow(SettingsProvider settings) async {
    if (_isBackingUp) return;

    setState(() {
      _isBackingUp = true;
      _backupProgress = 0.0;
      _backupStatusMessage = 'Preparing documents for backup...';
    });

    try {
      final docs = context.read<DocumentsProvider>().documents;
      int totalBytes = 0;
      for (final d in docs) {
        if (d.pdfPath != null) {
          final f = File(d.pdfPath!);
          if (f.existsSync()) totalBytes += f.lengthSync();
        }
      }

      final count = await GoogleDriveService.instance.backupAllDocuments(
        wifiOnly: settings.driveWifiOnly,
        includeMetadata: settings.driveIncludeMetadata,
        onProgress: (current, total, status) {
          if (mounted) {
            setState(() {
              _backupProgress = total > 0 ? (current / total).clamp(0.0, 1.0) : 0.0;
              _backupStatusMessage = status;
            });
          }
        },
      );

      await settings.recordLastBackup(
        date: DateTime.now(),
        count: count,
        size: totalBytes,
      );

      // Refresh local document sync states
      if (mounted) {
        await context.read<DocumentsProvider>().loadData();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backup successful! $count documents synced to Google Drive.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } on WifiRequiredException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: Colors.orange.shade800,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backup failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isBackingUp = false;
          _backupProgress = 0.0;
          _backupStatusMessage = '';
        });
      }
    }
  }

  void _showRestoreSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _DriveRestoreSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = context.watch<SettingsProvider>();
    final docsProvider = context.watch<DocumentsProvider>();

    final pendingCount = docsProvider.documents.where((d) => d.syncMetadata.status != SyncStatus.synced).length;
    final failedCount = docsProvider.documents.where((d) => d.syncMetadata.status == SyncStatus.failed).length;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Google Drive Backup'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: AppDimensions.screenPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Notice explaining Drive backup
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
                      Icons.cloud_sync_rounded,
                      size: 20,
                      color: isDark ? AppColors.darkPrimary : AppColors.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Google Drive backup synchronizes your PDF documents to a private "DocuRay Backups" folder. Files are safely encrypted and accessible offline.',
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

              // Real Sync Status Dashboard
              Text(
                'SYNC STATUS & METRICS',
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
                    _buildMetricRow(
                      'Account Connection',
                      settings.isDriveConnected ? (settings.driveUserEmail ?? 'Connected') : 'Disconnected',
                      settings.isDriveConnected ? AppColors.success : (isDark ? AppColors.darkTextSecondary : AppColors.textSecondary),
                      isDark,
                    ),
                    const Divider(),
                    _buildMetricRow(
                      'Last Successful Backup',
                      _formatDate(settings.lastBackupDate),
                      isDark ? AppColors.darkText : AppColors.textPrimary,
                      isDark,
                    ),
                    const Divider(),
                    _buildMetricRow(
                      'Last Successful Restore',
                      _formatDate(settings.lastRestoreDate),
                      isDark ? AppColors.darkText : AppColors.textPrimary,
                      isDark,
                    ),
                    const Divider(),
                    _buildMetricRow(
                      'Pending Uploads',
                      '$pendingCount local documents',
                      pendingCount > 0 ? Colors.orange : AppColors.success,
                      isDark,
                    ),
                    const Divider(),
                    _buildMetricRow(
                      'Failed Uploads',
                      '$failedCount documents',
                      failedCount > 0 ? AppColors.error : AppColors.success,
                      isDark,
                    ),
                    const Divider(),
                    _buildMetricRow(
                      'Current Operation',
                      _isBackingUp
                          ? 'Backing up...'
                          : (_isSigningIn ? 'Authenticating...' : 'Idle'),
                      _isBackingUp ? (isDark ? AppColors.darkPrimary : AppColors.primary) : (isDark ? AppColors.darkTextSecondary : AppColors.textSecondary),
                      isDark,
                    ),
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
            'Connect Google Drive',
            style: AppTypography.sectionTitle.copyWith(
              color: isDark ? AppColors.darkText : AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Back up your scanned documents and metadata securely to Google Drive. Keep your library safe and restore at any time.',
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(
              color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          if (_isSigningIn)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: CircularProgressIndicator(),
              ),
            )
          else
            PrimaryButton(
              label: 'Sign in with Google',
              icon: Icons.login_rounded,
              width: double.infinity,
              onPressed: () => _handleSignIn(settings),
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
                      settings.driveUserEmail ?? 'Google Account',
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
                onPressed: () => _handleDisconnect(settings),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Last Backup Summary Card
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'LAST BACKUP',
                    style: AppTypography.badge.copyWith(
                      color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                      letterSpacing: 1.0,
                    ),
                  ),
                  Text(
                    _formatDate(settings.lastBackupDate),
                    style: AppTypography.secondaryMedium.copyWith(
                      color: isDark ? AppColors.darkText : AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Documents backed up',
                    style: AppTypography.body.copyWith(
                      color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    '${settings.lastBackupCount} files',
                    style: AppTypography.bodyMedium.copyWith(
                      color: isDark ? AppColors.darkText : AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Cloud backup size',
                    style: AppTypography.body.copyWith(
                      color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    _formatBytes(settings.lastBackupSize),
                    style: AppTypography.bodyMedium.copyWith(
                      color: isDark ? AppColors.darkText : AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Backup Actions & Progress
        if (_isBackingUp) ...[
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _backupStatusMessage,
                        style: AppTypography.bodyMedium.copyWith(
                          color: isDark ? AppColors.darkText : AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _backupProgress > 0 ? _backupProgress : null,
                    backgroundColor: isDark ? const Color(0xFF262C34) : const Color(0xFFE2E8F0),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isDark ? AppColors.darkPrimary : AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ] else ...[
          Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  label: 'Back Up Now',
                  icon: Icons.backup_rounded,
                  onPressed: () => _handleBackupNow(settings),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SecondaryButton(
                  label: 'Restore',
                  icon: Icons.cloud_download_rounded,
                  onPressed: () => _showRestoreSheet(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],

        // Cloud Settings Toggles
        Text(
          'BACKUP PREFERENCES',
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
                subtitle: settings.isDriveConnected
                    ? 'Automatically sync scans when saved as PDF'
                    : 'Requires Google Drive connection to enable',
                value: settings.isDriveConnected && settings.driveAutoBackup,
                enabled: settings.isDriveConnected,
                onChanged: settings.isDriveConnected ? settings.setDriveAutoBackup : null,
              ),
              const Divider(),
              ToggleSettingTile(
                icon: Icons.wifi_rounded,
                title: 'Wi-Fi only',
                subtitle: 'Prevent mobile cellular data usage',
                value: settings.driveWifiOnly,
                onChanged: settings.setDriveWifiOnly,
              ),
              const Divider(),
              ToggleSettingTile(
                icon: Icons.description_outlined,
                title: 'Include Metadata',
                subtitle: 'Upload document ID, page count, and title tags',
                value: settings.driveIncludeMetadata,
                onChanged: settings.setDriveIncludeMetadata,
              ),
              const Divider(),
              SettingTile(
                icon: Icons.folder_outlined,
                title: 'Backup folder',
                subtitle: 'Google Drive > ${settings.driveBackupFolder}',
                trailing: const Icon(Icons.lock_outline_rounded, size: 16, color: Colors.grey),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetricRow(String label, String value, Color valueColor, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTypography.body.copyWith(
              color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodyMedium.copyWith(
                color: valueColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Modal Bottom Sheet for Selective Document Restore with Conflict Resolution
class _DriveRestoreSheet extends StatefulWidget {
  const _DriveRestoreSheet();

  @override
  State<_DriveRestoreSheet> createState() => _DriveRestoreSheetState();
}

class _DriveRestoreSheetState extends State<_DriveRestoreSheet> {
  bool _isLoading = true;
  bool _isRestoring = false;
  String _statusMsg = '';
  Map<String, DriveBackupEntry> _manifestEntries = {};
  final Set<String> _selectedEntryIds = {};
  ConflictResolution _resolution = ConflictResolution.keepBoth;

  @override
  void initState() {
    super.initState();
    _loadManifest();
  }

  Future<void> _loadManifest() async {
    setState(() => _isLoading = true);
    try {
      final entries = await GoogleDriveService.instance.fetchBackupManifest();
      setState(() {
        _manifestEntries = entries;
        _selectedEntryIds.addAll(entries.keys); // Default select all
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load cloud backups: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _executeRestore() async {
    if (_selectedEntryIds.isEmpty) return;

    setState(() {
      _isRestoring = true;
      _statusMsg = 'Restoring selected documents...';
    });

    int restoredCount = 0;
    try {
      final total = _selectedEntryIds.length;
      int idx = 0;

      for (final id in _selectedEntryIds) {
        final entry = _manifestEntries[id];
        if (entry != null) {
          idx++;
          setState(() {
            _statusMsg = 'Restoring "${entry.title}" ($idx/$total)...';
          });
          final restored = await GoogleDriveService.instance.restoreDocument(
            entry,
            resolution: _resolution,
          );
          if (restored != null) restoredCount++;
        }
      }

      if (mounted) {
        await context.read<SettingsProvider>().recordLastRestore(DateTime.now());
        if (!mounted) return;
        await context.read<DocumentsProvider>().loadData();
        if (!mounted) return;
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Restored $restoredCount documents successfully.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restore error: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isRestoring = false);
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final entries = _manifestEntries.values.toList();

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Restore from Google Drive',
                style: AppTypography.sectionTitle.copyWith(
                  color: isDark ? AppColors.darkText : AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (_isLoading)
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Reading backup manifest from Google Drive...'),
                  ],
                ),
              ),
            )
          else if (_isRestoring)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(_statusMsg, style: AppTypography.bodyMedium),
                  ],
                ),
              ),
            )
          else if (entries.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_off_rounded, size: 48, color: Colors.grey.withAlpha(120)),
                    const SizedBox(height: 12),
                    Text(
                      'No Cloud Backups Found',
                      style: AppTypography.subsectionTitle.copyWith(
                        color: isDark ? AppColors.darkText : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Use "Back Up Now" to save your local documents to Google Drive.',
                      textAlign: TextAlign.center,
                      style: AppTypography.secondary,
                    ),
                  ],
                ),
              ),
            )
          else ...[
            // Conflict Resolution Selector
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E232A) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? AppColors.darkBorder : AppColors.border,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'IF DOCUMENT ALREADY EXISTS:',
                    style: AppTypography.badge.copyWith(
                      color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonHideUnderline(
                    child: DropdownButton<ConflictResolution>(
                      value: _resolution,
                      isExpanded: true,
                      dropdownColor: isDark ? const Color(0xFF1E232A) : Colors.white,
                      style: AppTypography.bodyMedium.copyWith(
                        color: isDark ? AppColors.darkText : AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: ConflictResolution.keepBoth,
                          child: Text('Keep Both (Append Restored)'),
                        ),
                        DropdownMenuItem(
                          value: ConflictResolution.replace,
                          child: Text('Replace Existing Document'),
                        ),
                        DropdownMenuItem(
                          value: ConflictResolution.skip,
                          child: Text('Skip Existing Document'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _resolution = val);
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Select all / Deselect row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_selectedEntryIds.length} of ${entries.length} selected',
                  style: AppTypography.secondaryMedium,
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      if (_selectedEntryIds.length == entries.length) {
                        _selectedEntryIds.clear();
                      } else {
                        _selectedEntryIds.addAll(_manifestEntries.keys);
                      }
                    });
                  },
                  child: Text(
                    _selectedEntryIds.length == entries.length ? 'Deselect All' : 'Select All',
                  ),
                ),
              ],
            ),

            // Documents list
            Expanded(
              child: ListView.separated(
                itemCount: entries.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  final isSelected = _selectedEntryIds.contains(entry.id);

                  return CheckboxListTile(
                    value: isSelected,
                    activeColor: isDark ? AppColors.darkPrimary : AppColors.primary,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      entry.title,
                      style: AppTypography.bodyMedium.copyWith(
                        color: isDark ? AppColors.darkText : AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      '${entry.pageCount} ${entry.pageCount == 1 ? "page" : "pages"} · ${_formatBytes(entry.fileSize)}',
                      style: AppTypography.secondary,
                    ),
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _selectedEntryIds.add(entry.id);
                        } else {
                          _selectedEntryIds.remove(entry.id);
                        }
                      });
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // Restore action button
            PrimaryButton(
              label: 'Restore (${_selectedEntryIds.length})',
              icon: Icons.download_rounded,
              width: double.infinity,
              onPressed: _selectedEntryIds.isEmpty ? null : _executeRestore,
            ),
          ],
        ],
      ),
    );
  }
}
