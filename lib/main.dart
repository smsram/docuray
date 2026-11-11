import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'core/providers/settings_provider.dart';
import 'core/providers/documents_provider.dart';
import 'core/providers/scanner_provider.dart';
import 'core/providers/editor_provider.dart';
import 'core/providers/ai_provider.dart';
import 'core/routing/app_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
    ),
  );

  final settingsProvider = SettingsProvider();
  await settingsProvider.initialize();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(value: settingsProvider),
        ChangeNotifierProvider<DocumentsProvider>(create: (_) => DocumentsProvider()),
        ChangeNotifierProvider<ScannerProvider>(create: (_) => ScannerProvider()),
        ChangeNotifierProvider<EditorProvider>(create: (_) => EditorProvider()),
        ChangeNotifierProvider<AiProvider>(create: (_) => AiProvider()),
      ],
      child: const DocuRayApp(),
    ),
  );
}

class DocuRayApp extends StatelessWidget {
  final RouterConfig<Object>? routerConfig;

  const DocuRayApp({super.key, this.routerConfig});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return MaterialApp.router(
      title: 'DocuRay',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: settings.themeMode,
      routerConfig: routerConfig ?? AppRouter.router,
    );
  }
}
