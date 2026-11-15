import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:docuray/models/models.dart';
import 'package:docuray/core/providers/settings_provider.dart';
import 'package:docuray/core/providers/documents_provider.dart';
import 'package:docuray/core/providers/ai_provider.dart';
import 'package:docuray/core/services/google_drive_service.dart';
import 'package:docuray/core/services/hf_vision_service.dart';
import 'package:docuray/core/services/document_retrieval_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Part 1: Google Drive Backup & Settings State Verification', () {
    test('Wi-Fi Only is default OFF (false) and persists', () async {
      final settings = SettingsProvider();
      await settings.initialize();

      expect(settings.driveWifiOnly, isFalse, reason: 'Wi-Fi only must default to OFF');
      await settings.setDriveWifiOnly(true);
      expect(settings.driveWifiOnly, isTrue);

      final reloaded = SettingsProvider();
      await reloaded.initialize();
      expect(reloaded.driveWifiOnly, isTrue, reason: 'Must persist across reloads');
    });

    test('Include Metadata is default ON (true) and persists', () async {
      final settings = SettingsProvider();
      await settings.initialize();

      expect(settings.driveIncludeMetadata, isTrue, reason: 'Include Metadata must default to ON');
      await settings.setDriveIncludeMetadata(false);
      expect(settings.driveIncludeMetadata, isFalse);

      final reloaded = SettingsProvider();
      await reloaded.initialize();
      expect(reloaded.driveIncludeMetadata, isFalse, reason: 'Must persist across reloads');
    });

    test('Auto Backup is default OFF (false) and persists', () async {
      final settings = SettingsProvider();
      await settings.initialize();

      expect(settings.driveAutoBackup, isFalse, reason: 'Auto Backup must default to OFF');
      await settings.setDriveAutoBackup(true);
      expect(settings.driveAutoBackup, isTrue);
    });

    test('Last Restore Date records and persists', () async {
      final settings = SettingsProvider();
      await settings.initialize();

      expect(settings.lastRestoreDate, isNull);
      final now = DateTime.now();
      await settings.recordLastRestore(now);

      expect(settings.lastRestoreDate, isNotNull);
      expect(settings.lastRestoreDate, contains(now.year.toString()));
    });

    test('DriveBackupEntry serialization contains version, status, and checksum', () {
      final entry = DriveBackupEntry(
        id: 'doc_123',
        title: 'Tax Document',
        drivePdfFileId: 'drive_pdf_abc',
        driveMetaFileId: 'drive_meta_xyz',
        backupTimestamp: '2026-11-15T10:00:00.000Z',
        fileSize: 1048576,
        pageCount: 3,
        md5Checksum: 'd41d8cd98f00b204e9800998ecf8427e',
        version: 1,
        status: 'synced',
      );

      final json = entry.toJson();
      expect(json['id'], equals('doc_123'));
      expect(json['version'], equals(1));
      expect(json['status'], equals('synced'));
      expect(json['md5Checksum'], equals('d41d8cd98f00b204e9800998ecf8427e'));

      final parsed = DriveBackupEntry.fromJson(json);
      expect(parsed.id, equals('doc_123'));
      expect(parsed.version, equals(1));
      expect(parsed.status, equals('synced'));
      expect(parsed.md5Checksum, equals('d41d8cd98f00b204e9800998ecf8427e'));
    });

    test('ConflictResolution enum provides replace, keepBoth, and skip', () {
      expect(ConflictResolution.values.contains(ConflictResolution.replace), isTrue);
      expect(ConflictResolution.values.contains(ConflictResolution.keepBoth), isTrue);
      expect(ConflictResolution.values.contains(ConflictResolution.skip), isTrue);
    });
  });

  group('Part 2: Settings Functionality Verification', () {
    test('Auto Naming is default ON (true) and persists', () async {
      final settings = SettingsProvider();
      await settings.initialize();

      expect(settings.autoNaming, isTrue, reason: 'Auto Naming must default to ON');
      await settings.setAutoNaming(false);
      expect(settings.autoNaming, isFalse);

      final reloaded = SettingsProvider();
      await reloaded.initialize();
      expect(reloaded.autoNaming, isFalse, reason: 'Must persist across reloads');
    });

    test('Default scan options persist in SettingsProvider', () async {
      final settings = SettingsProvider();
      await settings.initialize();

      await settings.setDefaultScanMode('batch');
      await settings.setDefaultFilter('whiteboard');
      await settings.setScanQuality('high');
      await settings.setDefaultPdfQuality('standard');

      final reloaded = SettingsProvider();
      await reloaded.initialize();
      expect(reloaded.defaultScanMode, equals('batch'));
      expect(reloaded.defaultFilter, equals('whiteboard'));
      expect(reloaded.scanQuality, equals('high'));
      expect(reloaded.defaultPdfQuality, equals('standard'));
    });
  });

  group('Part 3: DocuRay AI Assistant & Vision Service Verification', () {
    test('HfVisionService configures Qwen3-VL-8B ZeroGPU endpoint & 120s limit', () {
      expect(HfVisionService.baseUrl, equals('https://smsram-zerogpu.hf.space'));
      expect(HfVisionService.dailyAllowanceSeconds, equals(120));

      final service = HfVisionService.instance;
      expect(service.remainingSecondsToday, lessThanOrEqualTo(120));
      expect(service.resetTimeFormatted, contains('midnight'));
    });

    test('Intelligent Retrieval Service extracts context and citations for multi-page documents', () {
      final service = DocumentRetrievalService.instance;

      final testDoc = Document(
        id: 'doc_contract_01',
        title: 'Master Service Agreement',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        ocrSummary: 'Confidential client contract with payment terms and liability clauses.',
        pages: const [
          DocumentPage(
            id: 'page_1',
            pageNumber: 1,
            filterType: 'auto',
            annotations: [
              AnnotationElement(
                id: 'ann_1',
                type: AnnotationType.text,
                points: [],
                text: 'Effective date January 1 2026',
              ),
            ],
          ),
          DocumentPage(
            id: 'page_2',
            pageNumber: 2,
            filterType: 'auto',
            annotations: [
              AnnotationElement(
                id: 'ann_2',
                type: AnnotationType.text,
                points: [],
                text: 'Total retainer fee is \$5,000 payable upon signing',
              ),
            ],
          ),
          DocumentPage(
            id: 'page_3',
            pageNumber: 3,
            filterType: 'auto',
            annotations: [
              AnnotationElement(
                id: 'ann_3',
                type: AnnotationType.text,
                points: [],
                text: 'Authorized signature by CEO and client',
              ),
            ],
          ),
        ],
      );

      // Query targeting retainer fee
      final retrievedFee = service.retrieveForQuery(
        document: testDoc,
        query: 'What is the total retainer fee?',
      );

      expect(retrievedFee.citedPages.contains(2), isTrue, reason: 'Page 2 contains retainer fee');
      expect(retrievedFee.formattedContext, contains('[Page 2]'));
      expect(retrievedFee.formattedContext, contains('Total retainer fee'));

      // Query targeting explicit page 3
      final retrievedP3 = service.retrieveForQuery(
        document: testDoc,
        query: 'Show me what is on page 3',
      );
      expect(retrievedP3.citedPages.first, equals(3), reason: 'Explicit page 3 request must prioritize page 3');
    });

    test('Auto Mode decision logic correctly identifies query intent', () {
      final service = DocumentRetrievalService.instance;
      final testDoc = Document(
        id: 'doc_sample',
        title: 'Physics Lab Report',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        pages: const [
          DocumentPage(id: 'p1', pageNumber: 1),
          DocumentPage(id: 'p2', pageNumber: 2),
        ],
      );

      // Summary query -> entireDoc
      final modeSummary = service.determineAutoMode(
        query: 'Can you summarize this document for me?',
        document: testDoc,
        currentPageIndex: 0,
      );
      expect(modeSummary, equals('entireDoc'));

      // Explicit page reference -> entireDoc
      final modePage = service.determineAutoMode(
        query: 'What does page 2 describe?',
        document: testDoc,
        currentPageIndex: 0,
      );
      expect(modePage, equals('entireDoc'));

      // Generic question -> noDocument
      final modeGeneral = service.determineAutoMode(
        query: 'What is the capital of Australia?',
        document: testDoc,
        currentPageIndex: 0,
      );
      expect(modeGeneral, equals('noDocument'));
    });

    test('AiProvider initializes document context and manages messages', () {
      final ai = AiProvider();

      ai.setDocumentContext(
        documentId: 'doc_sample_123',
        title: 'Q3 Financials',
        pageCount: 4,
        initialPageIndex: 2,
      );

      expect(ai.documentId, equals('doc_sample_123'));
      expect(ai.documentTitle, equals('Q3 Financials'));
      expect(ai.documentPageCount, equals(4));
      expect(ai.currentPageIndex, equals(2));
      expect(ai.messages.isNotEmpty, isTrue);
      expect(ai.messages.first.role, equals(MessageRole.assistant));
      expect(ai.messages.first.content, contains('Q3 Financials'));

      // Context mode toggling
      ai.setContextMode(AiContextMode.noDocument);
      expect(ai.contextMode, equals(AiContextMode.noDocument));

      ai.setContextMode(AiContextMode.currentPage);
      expect(ai.contextMode, equals(AiContextMode.currentPage));

      ai.setCurrentPageIndex(3);
      expect(ai.currentPageIndex, equals(3));

      // Clear conversation
      ai.clearConversation();
      expect(ai.messages, isEmpty);
    });

    test('AiProvider blocks execution if daily allowance is exhausted', () async {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      // Set usage to 120s (exhausted)
      await prefs.setString('ai_usage_date', todayStr);
      await prefs.setInt('ai_daily_usage_seconds', 120);

      final ai = AiProvider();
      await ai.sendMessage('Explain this page');

      expect(ai.errorMessage, contains('Daily free allowance reached'));
    });
  });

  group('Part 4: Storage Clearing, Drive Package Bundle & Simplified Filter Tests', () {
    test('DriveBackupEntry handles drivePackageFileId serialization and deserialization', () {
      final entry = DriveBackupEntry(
        id: 'doc_bundle_test',
        title: 'Project Proposal',
        drivePdfFileId: 'pdf_id_123',
        drivePackageFileId: 'pkg_id_456',
        driveMetaFileId: 'meta_id_789',
        backupTimestamp: '2026-11-15T10:00:00.000Z',
        fileSize: 2048576,
        pageCount: 5,
        md5Checksum: 'checksum123',
        version: 1,
        status: 'synced',
      );

      final json = entry.toJson();
      expect(json['drivePackageFileId'], equals('pkg_id_456'));

      final parsed = DriveBackupEntry.fromJson(json);
      expect(parsed.id, equals('doc_bundle_test'));
      expect(parsed.drivePackageFileId, equals('pkg_id_456'));
      expect(parsed.drivePdfFileId, equals('pdf_id_123'));
      expect(parsed.pageCount, equals(5));
    });

    test('AIMessage handles attachedImagePaths serialization and copyWith', () {
      final msg = AIMessage(
        id: 'msg_attach_1',
        role: MessageRole.user,
        content: 'Check this image',
        timestamp: DateTime.now(),
        attachedImagePaths: ['/cache/image1.jpg', '/cache/image2.jpg'],
      );

      expect(msg.attachedImagePaths, isNotNull);
      expect(msg.attachedImagePaths!.length, equals(2));
      expect(msg.attachedImagePaths!.first, equals('/cache/image1.jpg'));

      final copied = msg.copyWith(content: 'Updated prompt');
      expect(copied.content, equals('Updated prompt'));
      expect(copied.attachedImagePaths, equals(msg.attachedImagePaths));
    });

    test('DocumentFilter only contains all, pdfs, favorites (images removed)', () {
      // DocumentFilter.images was removed to avoid dead/misleading filter
      expect(DocumentFilter.values, equals([
        DocumentFilter.all,
        DocumentFilter.pdfs,
        DocumentFilter.favorites,
      ]));
      expect(DocumentFilter.values.length, equals(3));
    });
  });
}
