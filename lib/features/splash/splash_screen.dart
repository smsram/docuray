import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/providers/editor_provider.dart';
import '../../core/providers/scanner_provider.dart';
import '../../core/routing/app_router.dart';

/// Theme-aware splash screen matching the native launch background.
/// Light mode: #FFFFFF background with transparent centered master logo.
/// Dark mode: #111315 background with centered logo on a clean white rounded tile.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkNextDestination();
    });
  }

  Future<void> _cleanupTemporaryFiles() async {
    try {
      final tempDir = await getTemporaryDirectory();
      if (await tempDir.exists()) {
        final files = tempDir.listSync();
        for (final entity in files) {
          if (entity is File) {
            final name = entity.uri.pathSegments.last;
            // Clean up temporary capture files from aborted sessions
            if (name.startsWith('cap_') ||
                name.startsWith('raw_') ||
                name.startsWith('cropped_') ||
                name.startsWith('proc_') ||
                name.startsWith('preview_') ||
                name.endsWith('.tmp')) {
              try {
                await entity.delete();
              } catch (_) {}
            }
          }
        }
      }
    } catch (_) {}
  }

  void _checkNextDestination() {
    if (!mounted) return;
    try {
      context.read<ScannerProvider>().pauseCamera();
    } catch (_) {}

    // Asynchronously perform background cleanup without blocking instantaneous splash navigation
    EditorProvider.hasRecoveryDraft().then((hasDraft) {
      if (!hasDraft) {
        _cleanupTemporaryFiles();
      }
    }).catchError((_) {});

    final settings = context.read<SettingsProvider>();
    if (settings.isOnboardingCompleted) {
      context.go(AppRouter.home);
    } else {
      context.go(AppRouter.onboarding);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF111315) : const Color(0xFFFFFFFF),
      body: Center(
        child: Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(30),
                blurRadius: 18,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(12),
          child: SvgPicture.asset(
            'assets/branding/docuray_logo_bg.svg',
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
