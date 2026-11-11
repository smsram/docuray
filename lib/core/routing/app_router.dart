import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/splash/splash_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/shell/app_shell.dart';
import '../../features/home/home_screen.dart';
import '../../features/scanner/scanner_screen.dart';
import '../../features/import/import_screen.dart';
import '../../features/processing/processing_screen.dart';
import '../../features/editor/editor_screen.dart';
import '../../features/viewer/document_viewer_screen.dart';
import '../../features/ai/ai_assistant_screen.dart';
import '../../features/ai/ai_quick_action_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/drive/drive_settings_screen.dart';
import '../../features/ai_settings/ai_settings_screen.dart';
import '../../features/storage/storage_screen.dart';
import '../../features/folders/folders_screen.dart';
import '../../features/permissions/permissions_screen.dart';
import '../../features/about/about_screen.dart';
import '../../features/about/licenses_screen.dart';

/// Central routing configuration for DocuRay using GoRouter.
abstract class AppRouter {
  static const String splash = '/splash';
  static const String onboarding = '/onboarding';
  static const String home = '/home';
  static const String documents = '/documents';
  static const String scanner = '/scanner';
  static const String settings = '/settings';

  static const String importScreen = '/import';
  static const String processing = '/processing';
  static const String editor = '/editor';
  static const String viewer = '/viewer/:id';
  static const String aiAssistant = '/viewer/:id/ai';
  static const String aiQuickAction = '/viewer/:id/ai/quick-action';

  static const String driveSettings = '/settings/drive';
  static const String aiSettings = '/settings/ai';
  static const String storage = '/settings/storage';
  static const String folders = '/settings/folders';
  static const String permissions = '/settings/permissions';
  static const String about = '/settings/about';
  static const String licenses = '/settings/licenses';

  static GoRouter get router => _router;
  static final GoRouter _router = createRouter();

  static GoRouter createRouter({
    String initialLocation = splash,
    GlobalKey<NavigatorState>? rootNavigatorKey,
  }) {
    final rootKey = rootNavigatorKey ?? GlobalKey<NavigatorState>(debugLabel: 'root');
    final shellKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

    return GoRouter(
      navigatorKey: rootKey,
      initialLocation: initialLocation,
      routes: [
        // Splash screen
        GoRoute(
          path: splash,
          builder: (context, state) => const SplashScreen(),
        ),

        // Onboarding screen
        GoRoute(
          path: onboarding,
          builder: (context, state) => const OnboardingScreen(),
        ),

        // 4 Main destinations inside persistent App Shell
        ShellRoute(
          navigatorKey: shellKey,
          builder: (context, state, child) => AppShell(child: child),
          routes: [
            GoRoute(
              path: home,
              pageBuilder: (context, state) => const NoTransitionPage(
                child: HomeScreen(),
              ),
            ),
            GoRoute(
              path: settings,
              pageBuilder: (context, state) => const NoTransitionPage(
                child: SettingsScreen(),
              ),
            ),
          ],
        ),

        // Redirect /documents to /home
        GoRoute(
          path: documents,
          redirect: (context, state) => home,
        ),

        // Scanner screen (Full screen modal from prominent Scan button)
        GoRoute(
          path: scanner,
          parentNavigatorKey: rootKey,
          builder: (context, state) => const ScannerScreen(),
        ),

        // Import screen
        GoRoute(
          path: importScreen,
          parentNavigatorKey: rootKey,
          builder: (context, state) => const ImportScreen(),
        ),

        // Processing screen
        GoRoute(
          path: processing,
          parentNavigatorKey: rootKey,
          builder: (context, state) {
            final extra = state.extra as Map<String, dynamic>?;
            return ProcessingScreen(
              stepTitle: extra?['title'] as String?,
              destinationRoute: extra?['destination'] as String? ?? editor,
            );
          },
        ),

        // Editor screen
        GoRoute(
          path: editor,
          parentNavigatorKey: rootKey,
          builder: (context, state) {
            final extra = state.extra as Map<String, dynamic>?;
            return EditorScreen(
              documentId: extra?['documentId'] as String?,
            );
          },
        ),

        // Document Viewer (Receives documentId parameter in path)
        GoRoute(
          path: viewer,
          parentNavigatorKey: rootKey,
          builder: (context, state) {
            final id = state.pathParameters['id'] ?? '';
            return DocumentViewerScreen(documentId: id);
          },
        ),

        // Contextual AI Assistant
        GoRoute(
          path: aiAssistant,
          parentNavigatorKey: rootKey,
          builder: (context, state) {
            final id = state.pathParameters['id'] ?? '';
            return AiAssistantScreen(documentId: id);
          },
        ),

        // AI Quick Action Detail
        GoRoute(
          path: aiQuickAction,
          parentNavigatorKey: rootKey,
          builder: (context, state) {
            final id = state.pathParameters['id'] ?? '';
            final extra = state.extra as Map<String, dynamic>?;
            return AiQuickActionScreen(
              documentId: id,
              actionType: extra?['type'] as String? ?? 'summarize',
            );
          },
        ),

        // Sub-settings screens
        GoRoute(
          path: driveSettings,
          parentNavigatorKey: rootKey,
          builder: (context, state) => const DriveSettingsScreen(),
        ),
        GoRoute(
          path: aiSettings,
          parentNavigatorKey: rootKey,
          builder: (context, state) => const AiSettingsScreen(),
        ),
        GoRoute(
          path: storage,
          parentNavigatorKey: rootKey,
          builder: (context, state) => const StorageScreen(),
        ),
        GoRoute(
          path: folders,
          parentNavigatorKey: rootKey,
          builder: (context, state) => const FoldersScreen(),
        ),
        GoRoute(
          path: permissions,
          parentNavigatorKey: rootKey,
          builder: (context, state) => const PermissionsScreen(),
        ),
        GoRoute(
          path: about,
          parentNavigatorKey: rootKey,
          builder: (context, state) => const AboutScreen(),
        ),
        GoRoute(
          path: licenses,
          parentNavigatorKey: rootKey,
          builder: (context, state) => const LicensesScreen(),
        ),
      ],
    );
  }
}
