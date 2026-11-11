import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../services/document_repository.dart';

/// In-memory sample repository for Phase 1 UI demonstration.
class SampleDocumentRepository implements DocumentRepository {
  static final List<Folder> defaultFolders = [
    Folder(
      id: 'f-college',
      name: 'College',
      color: const Color(0xFF2563EB),
      icon: Icons.school_rounded,
      createdAt: DateTime.now().subtract(const Duration(days: 10)),
    ),
    Folder(
      id: 'f-work',
      name: 'Work',
      color: const Color(0xFF10B981),
      icon: Icons.work_rounded,
      createdAt: DateTime.now().subtract(const Duration(days: 8)),
    ),
    Folder(
      id: 'f-receipts',
      name: 'Receipts',
      color: const Color(0xFFF59E0B),
      icon: Icons.receipt_long_rounded,
      createdAt: DateTime.now().subtract(const Duration(days: 5)),
    ),
    Folder(
      id: 'f-personal',
      name: 'Personal',
      color: const Color(0xFF8B5CF6),
      icon: Icons.folder_rounded,
      createdAt: DateTime.now().subtract(const Duration(days: 3)),
    ),
  ];

  static List<Document> getInitialDocuments() {
    final now = DateTime.now();

    List<DocumentPage> generatePages(int count) {
      return List.generate(
        count,
        (index) => DocumentPage(
          id: 'page_${index + 1}',
          pageNumber: index + 1,
          filterType: 'auto',
          brightness: 0.0,
          contrast: 0.0,
          sharpness: 0.2,
        ),
      );
    }

    return [
      Document(
        id: 'doc-physics',
        title: 'Physics Notes',
        pages: generatePages(8),
        createdAt: now,
        updatedAt: now,
        isFavorite: true,
        folderId: 'f-college',
        format: DocumentFormat.pdf,
        fileSizeBytes: 3 * 1024 * 1024 + 450 * 1024,
        syncMetadata: SyncMetadata(
          status: SyncStatus.synced,
          lastSyncedAt: now.subtract(const Duration(minutes: 15)),
        ),
        ocrSummary: 'Classical mechanics, Newton laws of motion, gravitation theorems, kinetic energy equations and harmonic oscillators.',
      ),
      Document(
        id: 'doc-project',
        title: 'Project Report',
        pages: generatePages(14),
        createdAt: now.subtract(const Duration(days: 1)),
        updatedAt: now.subtract(const Duration(days: 1, hours: 2)),
        isFavorite: true,
        folderId: 'f-work',
        format: DocumentFormat.pdf,
        fileSizeBytes: 8 * 1024 * 1024 + 200 * 1024,
        syncMetadata: SyncMetadata(
          status: SyncStatus.synced,
          lastSyncedAt: now.subtract(const Duration(hours: 18)),
        ),
        ocrSummary: 'Annual engineering milestone analysis, performance benchmarks, distributed architecture diagrams and deployment roadmaps.',
      ),
      Document(
        id: 'doc-receipt',
        title: 'Fee Receipt',
        pages: generatePages(2),
        createdAt: now.subtract(const Duration(days: 2)),
        updatedAt: now.subtract(const Duration(days: 2)),
        isFavorite: false,
        folderId: 'f-receipts',
        format: DocumentFormat.pdf,
        fileSizeBytes: 820 * 1024,
        syncMetadata: const SyncMetadata(
          status: SyncStatus.notSynced,
        ),
        ocrSummary: 'Spring semester tuition payment invoice #TRX-88291. Amount received: \$1,250.00. Status: Paid in full.',
      ),
      Document(
        id: 'doc-assignment',
        title: 'College Assignment',
        pages: generatePages(6),
        createdAt: now.subtract(const Duration(days: 3)),
        updatedAt: now.subtract(const Duration(days: 3)),
        isFavorite: false,
        folderId: 'f-college',
        format: DocumentFormat.pdf,
        fileSizeBytes: 2 * 1024 * 1024 + 100 * 1024,
        syncMetadata: SyncMetadata(
          status: SyncStatus.synced,
          lastSyncedAt: now.subtract(const Duration(days: 2)),
        ),
        ocrSummary: 'Electromagnetic induction lab report, Maxwell equations derivations, experimental circuit data and error tolerance graphs.',
      ),
    ];
  }

  final List<Document> _documents = getInitialDocuments();
  final List<Folder> _folders = List.from(defaultFolders);

  @override
  Future<List<Document>> getAllDocuments() async {
    return List.unmodifiable(_documents);
  }

  @override
  Future<Document?> getDocumentById(String id) async {
    try {
      return _documents.firstWhere((d) => d.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveDocument(Document document) async {
    final index = _documents.indexWhere((d) => d.id == document.id);
    if (index >= 0) {
      _documents[index] = document;
    } else {
      _documents.insert(0, document);
    }
  }

  @override
  Future<void> deleteDocument(String id) async {
    _documents.removeWhere((d) => d.id == id);
  }

  @override
  Future<void> toggleFavorite(String id) async {
    final index = _documents.indexWhere((d) => d.id == id);
    if (index >= 0) {
      final doc = _documents[index];
      _documents[index] = doc.copyWith(isFavorite: !doc.isFavorite);
    }
  }

  @override
  Future<void> renameDocument(String id, String newTitle) async {
    final index = _documents.indexWhere((d) => d.id == id);
    if (index >= 0) {
      final doc = _documents[index];
      _documents[index] = doc.copyWith(title: newTitle, updatedAt: DateTime.now());
    }
  }

  @override
  Future<void> moveDocument(String id, String? folderId) async {
    final index = _documents.indexWhere((d) => d.id == id);
    if (index >= 0) {
      final doc = _documents[index];
      _documents[index] = doc.copyWith(folderId: folderId, updatedAt: DateTime.now());
    }
  }

  @override
  Future<List<Folder>> getFolders() async {
    return List.unmodifiable(_folders);
  }

  @override
  Future<void> createFolder(Folder folder) async {
    _folders.add(folder);
  }

  @override
  Future<void> deleteFolder(String folderId) async {
    _folders.removeWhere((f) => f.id == folderId);
  }
}
