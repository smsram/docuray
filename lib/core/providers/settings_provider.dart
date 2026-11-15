import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/models.dart';
import '../services/google_drive_service.dart';

/// App-wide settings and preference state with local persistence.
class SettingsProvider extends ChangeNotifier {
  static const String _keyThemeMode = 'theme_mode';
  static const String _keyOnboardingCompleted = 'onboarding_completed';
  static const String _keyAutoCapture = 'auto_capture';
  static const String _keyAutoEnhancement = 'auto_enhancement';
  static const String _keySaveAsPdf = 'save_as_pdf';
  static const String _keyDriveBackup = 'drive_backup';
  static const String _keyDriveAutoBackup = 'drive_auto_backup';
  static const String _keyDriveWifiOnly = 'drive_wifi_only';
  static const String _keyDriveIncludeMetadata = 'drive_include_metadata';
  static const String _keyLastBackupDate = 'last_backup_date';
  static const String _keyLastBackupCount = 'last_backup_count';
  static const String _keyLastBackupSize = 'last_backup_size';
  static const String _keyLastRestoreDate = 'last_restore_date';
  static const String _keyAutoNaming = 'auto_naming';

  static const String _keyAutoCaptureDefault = 'auto_capture_default';
  static const String _keyAutoCropDefault = 'auto_crop_default';
  static const String _keyDefaultFilter = 'default_filter';
  static const String _keyScanQuality = 'scan_quality';
  static const String _keyPdfQuality = 'pdf_quality';
  static const String _keyAppLock = 'app_lock';
  static const String _keyBiometricLock = 'biometric_lock';

  // Remember Editing Preferences Keys
  static const String _keyRememberFilter = 'remember_filter';
  static const String _keyRememberAdjustments = 'remember_adjustments';
  static const String _keyRememberResize = 'remember_resize';
  static const String _keyRememberMargins = 'remember_margins';
  static const String _keyRememberBorder = 'remember_border';
  static const String _keyRememberWatermark = 'remember_watermark';

  static const String _keyLastFilter = 'last_used_filter';
  static const String _keyLastBrightness = 'last_used_brightness';
  static const String _keyLastContrast = 'last_used_contrast';
  static const String _keyLastSharpness = 'last_used_sharpness';
  static const String _keyLastHighlights = 'last_used_highlights';
  static const String _keyLastShadows = 'last_used_shadows';
  static const String _keyLastExposure = 'last_used_exposure';
  static const String _keyLastSaturation = 'last_used_saturation';
  static const String _keyLastResizePreset = 'last_used_resize_preset';
  static const String _keyLastMarginTop = 'last_used_margin_top';
  static const String _keyLastMarginBottom = 'last_used_margin_bottom';
  static const String _keyLastMarginLeft = 'last_used_margin_left';
  static const String _keyLastMarginRight = 'last_used_margin_right';
  static const String _keyLastBorderEnabled = 'last_used_border_enabled';
  static const String _keyLastBorderThickness = 'last_used_border_thickness';
  static const String _keyLastBorderColor = 'last_used_border_color';
  static const String _keyLastBorderStyle = 'last_used_border_style';
  static const String _keyLastWatermarkText = 'last_used_watermark_text';
  static const String _keyLastWatermarkFontSize = 'last_used_watermark_font_size';
  static const String _keyLastWatermarkColor = 'last_used_watermark_color';
  static const String _keyLastWatermarkOpacity = 'last_used_watermark_opacity';
  static const String _keyLastWatermarkRotation = 'last_used_watermark_rotation';
  static const String _keyLastWatermarkPosition = 'last_used_watermark_position';

  ThemeMode _themeMode = ThemeMode.system;
  bool _isOnboardingCompleted = false;

  // Remember Editing Preferences Switches (Defaults)
  bool _rememberFilter = true;       // Default ON
  bool _rememberAdjustments = true;  // Default ON
  bool _rememberResize = true;       // Default ON
  bool _rememberMargins = true;      // Default ON
  bool _rememberBorder = true;       // Default ON
  bool _rememberWatermark = false;   // Default OFF

  // Last-used preference values
  String _lastFilter = 'original';
  double _lastBrightness = 0.0;
  double _lastContrast = 0.0;
  double _lastSharpness = 0.0;
  double _lastHighlights = 0.0;
  double _lastShadows = 0.0;
  double _lastExposure = 0.0;
  double _lastSaturation = 0.0;
  String _lastResizePreset = 'original';
  double _lastMarginTop = 0.0;
  double _lastMarginBottom = 0.0;
  double _lastMarginLeft = 0.0;
  double _lastMarginRight = 0.0;
  bool _lastBorderEnabled = false;
  double _lastBorderThickness = 2.0;
  int _lastBorderColor = 0xFF000000;
  String _lastBorderStyle = 'solid';
  String _lastWatermarkText = 'CONFIDENTIAL';
  double _lastWatermarkFontSize = 32.0;
  int _lastWatermarkColor = 0x6694A3B8;
  double _lastWatermarkOpacity = 0.35;
  double _lastWatermarkRotation = -35.0;
  String _lastWatermarkPosition = 'diagonal';

  // Onboarding & Scanning defaults
  bool _autoCapture = true;
  bool _autoEnhancement = true;
  bool _saveAsPdf = true;
  bool _driveBackup = false;

  bool _autoCaptureDefault = true;
  bool _autoCropDefault = true;

  String _defaultScanMode = 'Document';
  String _defaultFilter = 'Auto';
  String _scanQuality = 'High';
  String _defaultPdfQuality = 'Standard';
  bool _autoNaming = true;

  // Google Drive state (Real GoogleDriveService backing)
  bool _isDriveConnected = false;
  String? _driveUserEmail;
  bool _driveAutoBackup = false; // Default OFF per requirement
  bool _driveWifiOnly = false;   // Default OFF per requirement
  bool _driveIncludeMetadata = true; // Default ON per requirement
  String _driveBackupFolder = 'DocuRay Backups';
  SyncStatus _globalSyncStatus = SyncStatus.notSynced;
  String? _lastBackupDate;
  int _lastBackupCount = 0;
  int _lastBackupSize = 0;
  String? _lastRestoreDate;

  // AI settings
  String _aiProvider = 'Qwen3-VL-8B';
  bool _isAiConfigured = true;

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

  bool get autoCaptureDefault => _autoCaptureDefault;
  bool get autoCropDefault => _autoCropDefault;

  String get defaultScanMode => _defaultScanMode;
  String get defaultFilter => _defaultFilter;
  String get scanQuality => _scanQuality;
  String get defaultPdfQuality => _defaultPdfQuality;
  bool get autoNaming => _autoNaming;

  bool get isDriveConnected => _isDriveConnected;
  String? get driveUserEmail => _driveUserEmail;
  bool get driveAutoBackup => _driveAutoBackup;
  bool get driveWifiOnly => _driveWifiOnly;
  bool get driveIncludeMetadata => _driveIncludeMetadata;
  String get driveBackupFolder => _driveBackupFolder;
  SyncStatus get globalSyncStatus => _globalSyncStatus;
  String? get lastBackupDate => _lastBackupDate;
  int get lastBackupCount => _lastBackupCount;
  int get lastBackupSize => _lastBackupSize;
  String? get lastRestoreDate => _lastRestoreDate;

  String get aiProvider => _aiProvider;
  bool get isAiConfigured => _isAiConfigured;

  bool get appLock => _appLock;
  bool get biometricLock => _biometricLock;

  // Remember Editing Preferences Getters
  bool get rememberFilter => _rememberFilter;
  bool get rememberAdjustments => _rememberAdjustments;
  bool get rememberResize => _rememberResize;
  bool get rememberMargins => _rememberMargins;
  bool get rememberBorder => _rememberBorder;
  bool get rememberWatermark => _rememberWatermark;

  String get lastFilter => _lastFilter;
  double get lastBrightness => _lastBrightness;
  double get lastContrast => _lastContrast;
  double get lastSharpness => _lastSharpness;
  double get lastHighlights => _lastHighlights;
  double get lastShadows => _lastShadows;
  double get lastExposure => _lastExposure;
  double get lastSaturation => _lastSaturation;
  String get lastResizePreset => _lastResizePreset;
  PageMargins get lastMargins => PageMargins(
    top: _lastMarginTop,
    bottom: _lastMarginBottom,
    left: _lastMarginLeft,
    right: _lastMarginRight,
  );
  PageBorder get lastBorder => PageBorder(
    enabled: _lastBorderEnabled,
    thickness: _lastBorderThickness,
    colorValue: _lastBorderColor,
    style: _lastBorderStyle,
  );
  WatermarkConfig get lastWatermark => WatermarkConfig(
    enabled: false, // Never auto-applied by default
    text: _lastWatermarkText,
    fontSize: _lastWatermarkFontSize,
    colorValue: _lastWatermarkColor,
    opacity: _lastWatermarkOpacity,
    rotation: _lastWatermarkRotation,
    position: _lastWatermarkPosition,
  );

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

      _autoCaptureDefault = prefs.getBool(_keyAutoCaptureDefault) ?? true;
      _autoCropDefault = prefs.getBool(_keyAutoCropDefault) ?? true;

      _driveAutoBackup = prefs.getBool(_keyDriveAutoBackup) ?? false;
      _driveWifiOnly = prefs.getBool(_keyDriveWifiOnly) ?? false;
      _driveIncludeMetadata = prefs.getBool(_keyDriveIncludeMetadata) ?? true;
      _lastBackupDate = prefs.getString(_keyLastBackupDate);
      _lastBackupCount = prefs.getInt(_keyLastBackupCount) ?? 0;
      _lastBackupSize = prefs.getInt(_keyLastBackupSize) ?? 0;
      _lastRestoreDate = prefs.getString(_keyLastRestoreDate);

      _autoNaming = prefs.getBool(_keyAutoNaming) ?? true;
      _defaultScanMode = prefs.getString('default_scan_mode') ?? 'Document';
      _defaultFilter = prefs.getString(_keyDefaultFilter) ?? 'Auto';
      _scanQuality = prefs.getString(_keyScanQuality) ?? 'High';
      _defaultPdfQuality = prefs.getString(_keyPdfQuality) ?? 'Standard';
      _appLock = prefs.getBool(_keyAppLock) ?? false;
      _biometricLock = prefs.getBool(_keyBiometricLock) ?? false;

      // Silent Google Sign-In attempt
      try {
        final signedIn = await GoogleDriveService.instance.initSilentSignIn();
        if (signedIn) {
          _isDriveConnected = true;
          _driveUserEmail = GoogleDriveService.instance.currentUserEmail;
          _globalSyncStatus = SyncStatus.synced;
        }
      } catch (_) {}

      // Remember Editing Preferences Persistence
      _rememberFilter = prefs.getBool(_keyRememberFilter) ?? true;
      _rememberAdjustments = prefs.getBool(_keyRememberAdjustments) ?? true;
      _rememberResize = prefs.getBool(_keyRememberResize) ?? true;
      _rememberMargins = prefs.getBool(_keyRememberMargins) ?? true;
      _rememberBorder = prefs.getBool(_keyRememberBorder) ?? true;
      _rememberWatermark = prefs.getBool(_keyRememberWatermark) ?? false;

      _lastFilter = prefs.getString(_keyLastFilter) ?? 'original';
      _lastBrightness = prefs.getDouble(_keyLastBrightness) ?? 0.0;
      _lastContrast = prefs.getDouble(_keyLastContrast) ?? 0.0;
      _lastSharpness = prefs.getDouble(_keyLastSharpness) ?? 0.0;
      _lastHighlights = prefs.getDouble(_keyLastHighlights) ?? 0.0;
      _lastShadows = prefs.getDouble(_keyLastShadows) ?? 0.0;
      _lastExposure = prefs.getDouble(_keyLastExposure) ?? 0.0;
      _lastSaturation = prefs.getDouble(_keyLastSaturation) ?? 0.0;
      _lastResizePreset = prefs.getString(_keyLastResizePreset) ?? 'original';
      _lastMarginTop = prefs.getDouble(_keyLastMarginTop) ?? 0.0;
      _lastMarginBottom = prefs.getDouble(_keyLastMarginBottom) ?? 0.0;
      _lastMarginLeft = prefs.getDouble(_keyLastMarginLeft) ?? 0.0;
      _lastMarginRight = prefs.getDouble(_keyLastMarginRight) ?? 0.0;
      _lastBorderEnabled = prefs.getBool(_keyLastBorderEnabled) ?? false;
      _lastBorderThickness = prefs.getDouble(_keyLastBorderThickness) ?? 2.0;
      _lastBorderColor = prefs.getInt(_keyLastBorderColor) ?? 0xFF000000;
      _lastBorderStyle = prefs.getString(_keyLastBorderStyle) ?? 'solid';
      _lastWatermarkText = prefs.getString(_keyLastWatermarkText) ?? 'CONFIDENTIAL';
      _lastWatermarkFontSize = prefs.getDouble(_keyLastWatermarkFontSize) ?? 32.0;
      _lastWatermarkColor = prefs.getInt(_keyLastWatermarkColor) ?? 0x6694A3B8;
      _lastWatermarkOpacity = prefs.getDouble(_keyLastWatermarkOpacity) ?? 0.35;
      _lastWatermarkRotation = prefs.getDouble(_keyLastWatermarkRotation) ?? -35.0;
      _lastWatermarkPosition = prefs.getString(_keyLastWatermarkPosition) ?? 'diagonal';

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

  Future<void> setAutoEnhancement(bool val) async {
    _autoEnhancement = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoEnhancement, val);
  }

  void setSaveAsPdf(bool val) {
    _saveAsPdf = val;
    notifyListeners();
  }

  Future<void> setDefaultScanMode(String mode) async {
    _defaultScanMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('default_scan_mode', mode);
  }

  Future<void> setDefaultFilter(String filter) async {
    _defaultFilter = filter;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDefaultFilter, filter);
  }

  Future<void> setScanQuality(String quality) async {
    _scanQuality = quality;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyScanQuality, quality);
  }

  Future<void> setDefaultPdfQuality(String quality) async {
    _defaultPdfQuality = quality;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPdfQuality, quality);
  }

  Future<void> setAutoNaming(bool val) async {
    _autoNaming = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoNaming, val);
  }

  Future<void> setAutoCaptureDefault(bool val) async {
    _autoCaptureDefault = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoCaptureDefault, val);
  }

  Future<void> setAutoCropDefault(bool val) async {
    _autoCropDefault = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoCropDefault, val);
  }

  // Google Drive actions (Real GoogleDriveService integration)
  Future<bool> signInGoogleDrive() async {
    try {
      final account = await GoogleDriveService.instance.signIn();
      if (account != null) {
        _isDriveConnected = true;
        _driveUserEmail = account.email;
        _globalSyncStatus = SyncStatus.synced;
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('[DocuRay Settings] Google Sign-In error: $e');
      rethrow;
    }
    return false;
  }

  Future<void> disconnectGoogleDrive() async {
    await GoogleDriveService.instance.disconnect();
    _isDriveConnected = false;
    _driveUserEmail = null;
    _globalSyncStatus = SyncStatus.notSynced;
    notifyListeners();
  }

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

  Future<void> setDriveAutoBackup(bool val) async {
    _driveAutoBackup = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDriveAutoBackup, val);
  }

  Future<void> setDriveWifiOnly(bool val) async {
    _driveWifiOnly = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDriveWifiOnly, val);
  }

  Future<void> setDriveIncludeMetadata(bool val) async {
    _driveIncludeMetadata = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDriveIncludeMetadata, val);
  }

  Future<void> recordLastRestore(DateTime date) async {
    _lastRestoreDate = date.toIso8601String();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastRestoreDate, _lastRestoreDate!);
  }

  Future<void> recordLastBackup({
    required DateTime date,
    required int count,
    required int size,
  }) async {
    _lastBackupDate = date.toIso8601String();
    _lastBackupCount = count;
    _lastBackupSize = size;
    _globalSyncStatus = SyncStatus.synced;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastBackupDate, _lastBackupDate!);
    await prefs.setInt(_keyLastBackupCount, count);
    await prefs.setInt(_keyLastBackupSize, size);
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

  // Remember Editing Preferences Toggle Actions
  Future<void> setRememberFilter(bool val) async {
    _rememberFilter = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyRememberFilter, val);
  }

  Future<void> setRememberAdjustments(bool val) async {
    _rememberAdjustments = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyRememberAdjustments, val);
  }

  Future<void> setRememberResize(bool val) async {
    _rememberResize = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyRememberResize, val);
  }

  Future<void> setRememberMargins(bool val) async {
    _rememberMargins = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyRememberMargins, val);
  }

  Future<void> setRememberBorder(bool val) async {
    _rememberBorder = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyRememberBorder, val);
  }

  Future<void> setRememberWatermark(bool val) async {
    _rememberWatermark = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyRememberWatermark, val);
  }

  // Record Last-Used Preferences
  Future<void> recordLastUsedFilter(String filter) async {
    _lastFilter = filter;
    if (_rememberFilter) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyLastFilter, filter);
    }
  }

  Future<void> recordLastUsedAdjustments({
    required double brightness,
    required double contrast,
    required double sharpness,
    required double highlights,
    required double shadows,
    required double exposure,
    required double saturation,
  }) async {
    _lastBrightness = brightness;
    _lastContrast = contrast;
    _lastSharpness = sharpness;
    _lastHighlights = highlights;
    _lastShadows = shadows;
    _lastExposure = exposure;
    _lastSaturation = saturation;

    if (_rememberAdjustments) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_keyLastBrightness, brightness);
      await prefs.setDouble(_keyLastContrast, contrast);
      await prefs.setDouble(_keyLastSharpness, sharpness);
      await prefs.setDouble(_keyLastHighlights, highlights);
      await prefs.setDouble(_keyLastShadows, shadows);
      await prefs.setDouble(_keyLastExposure, exposure);
      await prefs.setDouble(_keyLastSaturation, saturation);
    }
  }

  Future<void> recordLastUsedResize(String preset) async {
    _lastResizePreset = preset;
    if (_rememberResize) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyLastResizePreset, preset);
    }
  }

  Future<void> recordLastUsedMargins(PageMargins margins) async {
    _lastMarginTop = margins.top;
    _lastMarginBottom = margins.bottom;
    _lastMarginLeft = margins.left;
    _lastMarginRight = margins.right;

    if (_rememberMargins) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_keyLastMarginTop, margins.top);
      await prefs.setDouble(_keyLastMarginBottom, margins.bottom);
      await prefs.setDouble(_keyLastMarginLeft, margins.left);
      await prefs.setDouble(_keyLastMarginRight, margins.right);
    }
  }

  Future<void> recordLastUsedBorder(PageBorder border) async {
    _lastBorderEnabled = border.enabled;
    _lastBorderThickness = border.thickness;
    _lastBorderColor = border.colorValue;
    _lastBorderStyle = border.style;

    if (_rememberBorder) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyLastBorderEnabled, border.enabled);
      await prefs.setDouble(_keyLastBorderThickness, border.thickness);
      await prefs.setInt(_keyLastBorderColor, border.colorValue);
      await prefs.setString(_keyLastBorderStyle, border.style);
    }
  }

  Future<void> recordLastUsedWatermark(WatermarkConfig watermark) async {
    _lastWatermarkText = watermark.text;
    _lastWatermarkFontSize = watermark.fontSize;
    _lastWatermarkColor = watermark.colorValue;
    _lastWatermarkOpacity = watermark.opacity;
    _lastWatermarkRotation = watermark.rotation;
    _lastWatermarkPosition = watermark.position;

    if (_rememberWatermark) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyLastWatermarkText, watermark.text);
      await prefs.setDouble(_keyLastWatermarkFontSize, watermark.fontSize);
      await prefs.setInt(_keyLastWatermarkColor, watermark.colorValue);
      await prefs.setDouble(_keyLastWatermarkOpacity, watermark.opacity);
      await prefs.setDouble(_keyLastWatermarkRotation, watermark.rotation);
      await prefs.setString(_keyLastWatermarkPosition, watermark.position);
    }
  }

  /// Records all preferences from a given page into last-used settings.
  Future<void> recordPreferencesFromPage(DocumentPage page) async {
    await recordLastUsedFilter(page.filterType);
    await recordLastUsedAdjustments(
      brightness: page.brightness,
      contrast: page.contrast,
      sharpness: page.sharpness,
      highlights: page.highlights,
      shadows: page.shadows,
      exposure: page.exposure,
      saturation: page.saturation,
    );
    await recordLastUsedResize(page.resize.preset);
    await recordLastUsedMargins(page.margins);
    await recordLastUsedBorder(page.border);
    await recordLastUsedWatermark(page.watermark);
  }

  /// Applies remembered preferences to newly captured / imported page.
  /// Watermark is NEVER automatically enabled by default.
  DocumentPage applyPreferencesToNewPage(DocumentPage rawPage) {
    return rawPage.copyWith(
      filterType: _rememberFilter ? _lastFilter : 'original',
      brightness: _rememberAdjustments ? _lastBrightness : 0.0,
      contrast: _rememberAdjustments ? _lastContrast : 0.0,
      sharpness: _rememberAdjustments ? _lastSharpness : 0.0,
      highlights: _rememberAdjustments ? _lastHighlights : 0.0,
      shadows: _rememberAdjustments ? _lastShadows : 0.0,
      exposure: _rememberAdjustments ? _lastExposure : 0.0,
      saturation: _rememberAdjustments ? _lastSaturation : 0.0,
      resize: _rememberResize ? PageResizeConfig(preset: _lastResizePreset) : const PageResizeConfig(),
      margins: _rememberMargins ? lastMargins : const PageMargins(),
      border: _rememberBorder ? lastBorder : const PageBorder(),
      watermark: _rememberWatermark ? lastWatermark.copyWith(enabled: false) : const WatermarkConfig(enabled: false),
    );
  }
}
