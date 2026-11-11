import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:docuray/main.dart';
import 'package:docuray/core/routing/app_router.dart';
import 'package:docuray/core/providers/settings_provider.dart';
import 'package:docuray/core/providers/documents_provider.dart';
import 'package:docuray/core/providers/scanner_provider.dart';
import 'package:docuray/core/providers/editor_provider.dart';
import 'package:docuray/core/providers/ai_provider.dart';
import 'package:docuray/models/models.dart';
import 'package:docuray/core/services/document_repository.dart';
import 'package:docuray/features/splash/splash_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('DocuRay app starts, shows splash, and navigates to onboarding', (WidgetTester tester) async {
    final settingsProvider = SettingsProvider();
    final router = AppRouter.createRouter(initialLocation: AppRouter.splash);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settingsProvider),
          ChangeNotifierProvider<DocumentsProvider>(create: (_) => DocumentsProvider()),
          ChangeNotifierProvider<ScannerProvider>(create: (_) => ScannerProvider()),
          ChangeNotifierProvider<EditorProvider>(create: (_) => EditorProvider()),
          ChangeNotifierProvider<AiProvider>(create: (_) => AiProvider()),
        ],
        child: DocuRayApp(routerConfig: router),
      ),
    );

    // Initial frame renders Splash branding screen
    expect(find.byType(SplashScreen), findsOneWidget);

    // Fast-forward past splash transition
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    // Verify Onboarding Screen appears
    expect(find.text('Scan paper into clean digital documents.'), findsOneWidget);
  });

  testWidgets('DocuRay direct home screen displays empty state on fresh install', (WidgetTester tester) async {
    final settingsProvider = SettingsProvider();
    final docsProvider = DocumentsProvider(repository: MockEmptyDocumentRepository());
    final router = AppRouter.createRouter(initialLocation: AppRouter.home);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settingsProvider),
          ChangeNotifierProvider<DocumentsProvider>.value(value: docsProvider),
          ChangeNotifierProvider<ScannerProvider>(create: (_) => ScannerProvider()),
          ChangeNotifierProvider<EditorProvider>(create: (_) => EditorProvider()),
          ChangeNotifierProvider<AiProvider>(create: (_) => AiProvider()),
        ],
        child: DocuRayApp(routerConfig: router),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify Home Screen empty state on fresh install
    expect(find.text('No documents yet'), findsOneWidget);
    expect(find.text('Scan document'), findsOneWidget);
    expect(find.text('Search documents...'), findsOneWidget);
  });

  testWidgets('Theme switching toggles dark and light themes smoothly', (WidgetTester tester) async {
    final settingsProvider = SettingsProvider();

    await settingsProvider.setThemeMode(ThemeMode.dark);
    expect(settingsProvider.themeMode, ThemeMode.dark);

    await settingsProvider.setThemeMode(ThemeMode.light);
    expect(settingsProvider.themeMode, ThemeMode.light);
  });
}

class MockEmptyDocumentRepository implements DocumentRepository {
  @override
  Future<List<Document>> getAllDocuments() async => [];
  @override
  Future<List<Folder>> getFolders() async => [];
  @override
  Future<void> saveDocument(Document doc) async {}
  @override
  Future<void> deleteDocument(String id) async {}
  @override
  Future<void> renameDocument(String id, String newTitle) async {}
  @override
  Future<void> toggleFavorite(String id) async {}
  @override
  Future<void> moveDocument(String id, String? folderId) async {}
  @override
  Future<Document?> getDocumentById(String id) async => null;
  @override
  Future<void> createFolder(Folder folder) async {}
  @override
  Future<void> deleteFolder(String folderId) async {}
}
