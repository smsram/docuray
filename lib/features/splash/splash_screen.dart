import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/providers/settings_provider.dart';
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

  void _checkNextDestination() {
    if (!mounted) return;
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
        child: isDark
            ? Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(40),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(20),
                child: SvgPicture.asset(
                  'assets/branding/docuray_logo.svg',
                  fit: BoxFit.contain,
                ),
              )
            : SvgPicture.asset(
                'assets/branding/docuray_logo.svg',
                width: 100,
                height: 100,
                fit: BoxFit.contain,
              ),
      ),
    );
  }
}
