import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/models.dart';

/// App-wide settings and preference state with local persistence.
class SettingsProvider extends ChangeNotifier {
  static const String _keyThemeMode = 'theme_mode';
  static const String _keyOnboardingCompleted = 'onboarding_completed';
  static const String _keyAutoCapture = 'auto_capture';
  static const String _keyAutoEnhancement = 'auto_enhancement';
  static const String _keySaveAsPdf = 'save_as_pdf';
  static const String _keyDriveBackup = 'drive_backup';
  static const String _keyDefaultFilter = 'default_filter';
  static const String _keyScanQuality = 'scan_quality';
  static const String _keyPdfQuality = 'pdf_quality';
  static const String _keyAppLock = 'app_lock';
  static const String _keyBiometricLock = 'biometric_lock';

  ThemeMode _themeMode = ThemeMode.system;
  bool _isOnboardingCompleted = false;

  // Onboarding & Scanning defaults
  bool _autoCapture = true;
  bool _autoEnhancement = true;
  bool _saveAsPdf = true;
  bool _driveBackup = false;

  String _defaultScanMode = 'Document';
  String _defaultFilter = 'Auto';
  String _scanQuality = 'High';
  String _defaultPdfQuality = 'Standard';

  // Google Drive state (UI representation)
  bool _isDriveConnected = false;
  String? _driveUserEmail;
  bool _driveAutoBackup = true;
  bool _driveWifiOnly = true;
  String _driveBackupFolder = 'My Scanner';
  SyncStatus _globalSyncStatus = SyncStatus.notSynced;

  // AI settings
  String _aiProvider = 'Gemini';
  bool _isAiConfigured = false;

  // Privacy & security
  bool _appLock = false;
  bool _biometricLock = false;

  // Getters
  ThemeMode get themeMode => _themeMode;
  bool get isOnboardingCompleted => _isOnboardingCompleted;
  bool get autoCapture => _autoCapture;
  bool get autoEnhancement => _autoEnhancement;
  bool get saveAsPdf => _saveAsPdf;
  bool get driveBackup => _driveBackup;
  String get defaultScanMode => _defaultScanMode;
  String get defaultFilter => _defaultFilter;
  String get scanQuality => _scanQuality;
  String get defaultPdfQuality => _defaultPdfQuality;

  bool get isDriveConnected => _isDriveConnected;
  String? get driveUserEmail => _driveUserEmail;
  bool get driveAutoBackup => _driveAutoBackup;
  bool get driveWifiOnly => _driveWifiOnly;
  String get driveBackupFolder => _driveBackupFolder;
  SyncStatus get globalSyncStatus => _globalSyncStatus;

  String get aiProvider => _aiProvider;
  bool get isAiConfigured => _isAiConfigured;

  bool get appLock => _appLock;
  bool get biometricLock => _biometricLock;

  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final savedTheme = prefs.getString(_keyThemeMode);
      if (savedTheme == 'dark') {
        _themeMode = ThemeMode.dark;
      } else if (savedTheme == 'light') {
        _themeMode = ThemeMode.light;
      } else {
        _themeMode = ThemeMode.system;
      }

      _isOnboardingCompleted = prefs.getBool(_keyOnboardingCompleted) ?? false;
      _autoCapture = prefs.getBool(_keyAutoCapture) ?? true;
      _autoEnhancement = prefs.getBool(_keyAutoEnhancement) ?? true;
      _saveAsPdf = prefs.getBool(_keySaveAsPdf) ?? true;
      _driveBackup = prefs.getBool(_keyDriveBackup) ?? false;
      _defaultFilter = prefs.getString(_keyDefaultFilter) ?? 'Auto';
      _scanQuality = prefs.getString(_keyScanQuality) ?? 'High';
      _defaultPdfQuality = prefs.getString(_keyPdfQuality) ?? 'Standard';
      _appLock = prefs.getBool(_keyAppLock) ?? false;
      _biometricLock = prefs.getBool(_keyBiometricLock) ?? false;

      notifyListeners();
    } catch (_) {
      // Fallback defaults on any storage error
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeStr = mode == ThemeMode.dark
          ? 'dark'
          : (mode == ThemeMode.system ? 'system' : 'light');
      await prefs.setString(_keyThemeMode, modeStr);
    } catch (_) {}
  }

  Future<void> completeOnboarding({
    bool? autoCapture,
    bool? autoEnhancement,
    bool? saveAsPdf,
    bool? driveBackup,
  }) async {
    _isOnboardingCompleted = true;
    if (autoCapture != null) _autoCapture = autoCapture;
    if (autoEnhancement != null) _autoEnhancement = autoEnhancement;
    if (saveAsPdf != null) _saveAsPdf = saveAsPdf;
    if (driveBackup != null) _driveBackup = driveBackup;

    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyOnboardingCompleted, true);
      await prefs.setBool(_keyAutoCapture, _autoCapture);
      await prefs.setBool(_keyAutoEnhancement, _autoEnhancement);
      await prefs.setBool(_keySaveAsPdf, _saveAsPdf);
      await prefs.setBool(_keyDriveBackup, _driveBackup);
    } catch (_) {}
  }

  void setAutoCapture(bool val) {
    _autoCapture = val;
    notifyListeners();
  }

  void setAutoEnhancement(bool val) {
    _autoEnhancement = val;
    notifyListeners();
  }

  void setSaveAsPdf(bool val) {
    _saveAsPdf = val;
    notifyListeners();
  }

  void setDefaultScanMode(String mode) {
    _defaultScanMode = mode;
    notifyListeners();
  }

  void setDefaultFilter(String filter) {
    _defaultFilter = filter;
    notifyListeners();
  }

  void setScanQuality(String quality) {
    _scanQuality = quality;
    notifyListeners();
  }

  void setDefaultPdfQuality(String quality) {
    _defaultPdfQuality = quality;
    notifyListeners();
  }

  // Google Drive actions (UI state simulation for Phase 1)
  void connectDrive(String email) {
    _isDriveConnected = true;
    _driveUserEmail = email;
    _globalSyncStatus = SyncStatus.synced;
    notifyListeners();
  }

  void disconnectDrive() {
    _isDriveConnected = false;
    _driveUserEmail = null;
    _globalSyncStatus = SyncStatus.notSynced;
    notifyListeners();
  }

  void setDriveAutoBackup(bool val) {
    _driveAutoBackup = val;
    notifyListeners();
  }

  void setDriveWifiOnly(bool val) {
    _driveWifiOnly = val;
    notifyListeners();
  }

  void setDriveBackupFolder(String folder) {
    _driveBackupFolder = folder;
    notifyListeners();
  }

  // AI
  void setAiProvider(String provider) {
    _aiProvider = provider;
    notifyListeners();
  }

  void setAiConfigured(bool configured) {
    _isAiConfigured = configured;
    notifyListeners();
  }

  // Privacy
  void setAppLock(bool val) {
    _appLock = val;
    notifyListeners();
  }

  void setBiometricLock(bool val) {
    _biometricLock = val;
    notifyListeners();
  }
}
