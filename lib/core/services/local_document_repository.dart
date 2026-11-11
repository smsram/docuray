import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../models/models.dart';
import 'document_repository.dart';

/// Real persistent filesystem and metadata repository for DocuRay documents.
/// Persists documents across app restarts in the application documents directory.
class LocalDocumentRepository implements DocumentRepository {
  static final LocalDocumentRepository instance = LocalDocumentRepository();

  static const String _manifestFilename = 'docuray_manifest.json';
  static const String _documentsDirName = 'documents';

  Directory? _baseDir;
  File? _manifestFile;
  final List<Document> _documentsCache = [];
  final List<Folder> _foldersCache = [];
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;

    final appDocDir = await getApplicationDocumentsDirectory();
    _baseDir = Directory('${appDocDir.path}/$_documentsDirName');
    if (!await _baseDir!.exists()) {
      await _baseDir!.create(recursive: true);
    }

    _manifestFile = File('${appDocDir.path}/$_manifestFilename');
    if (await _manifestFile!.exists()) {
      try {
        final content = await _manifestFile!.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;

        _documentsCache.clear();
        if (data['documents'] != null) {
          for (final item in data['documents'] as List<dynamic>) {
            _documentsCache.add(Document.fromJson(item as Map<String, dynamic>));
          }
        }

        _foldersCache.clear();
        if (data['folders'] != null) {
          for (final item in data['folders'] as List<dynamic>) {
            _foldersCache.add(Folder.fromJson(item as Map<String, dynamic>));
          }
        }
      } catch (e) {
        // Fallback: load directly from individual document folders if manifest corrupted
        await _recoverFromFilesystem();
      }
    }

    _initialized = true;
  }

  Future<void> _recoverFromFilesystem() async {
    if (_baseDir == null || !await _baseDir!.exists()) return;

    _documentsCache.clear();
    final entities = _baseDir!.listSync();
    for (final entity in entities) {
      if (entity is Directory) {
        final metaFile = File('${entity.path}/meta.json');
        if (metaFile.existsSync()) {
          try {
            final content = metaFile.readAsStringSync();
            final doc = Document.fromJson(jsonDecode(content));
            _documentsCache.add(doc);
          } catch (_) {}
        }
      }
    }
  }

  Future<void> _persistManifest() async {
    if (_manifestFile == null) return;

    final data = {
      'version': 1,
      'updatedAt': DateTime.now().toIso8601String(),
      'documents': _documentsCache.map((d) => d.toJson()).toList(),
      'folders': _foldersCache.map((f) => f.toJson()).toList(),
    };

    await _manifestFile!.writeAsString(jsonEncode(data), flush: true);
  }

  @override
  Future<List<Document>> getAllDocuments() async {
    await _ensureInitialized();
    final list = List<Document>.from(_documentsCache);
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  @override
  Future<Document?> getDocumentById(String id) async {
    await _ensureInitialized();
    try {
      return _documentsCache.firstWhere((d) => d.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveDocument(Document document) async {
    await _ensureInitialized();

    // Ensure document directory exists
    final docDir = Directory('${_baseDir!.path}/${document.id}');
    if (!await docDir.exists()) {
      await docDir.create(recursive: true);
    }

    // Save individual meta.json in the document folder
    final metaFile = File('${docDir.path}/meta.json');
    await metaFile.writeAsString(jsonEncode(document.toJson()), flush: true);

    final index = _documentsCache.indexWhere((d) => d.id == document.id);
    if (index >= 0) {
      _documentsCache[index] = document;
    } else {
      _documentsCache.add(document);
    }

    await _persistManifest();
  }

  @override
  Future<void> deleteDocument(String id) async {
    await _ensureInitialized();

    _documentsCache.removeWhere((d) => d.id == id);

    // Delete folder and all its contents
    final docDir = Directory('${_baseDir!.path}/$id');
    if (await docDir.exists()) {
      try {
        await docDir.delete(recursive: true);
      } catch (_) {}
    }

    await _persistManifest();
  }

  @override
  Future<void> toggleFavorite(String id) async {
    await _ensureInitialized();
    final index = _documentsCache.indexWhere((d) => d.id == id);
    if (index >= 0) {
      final doc = _documentsCache[index];
      final updated = doc.copyWith(
        isFavorite: !doc.isFavorite,
        updatedAt: DateTime.now(),
      );
      _documentsCache[index] = updated;

      // Update disk
      final metaFile = File('${_baseDir!.path}/$id/meta.json');
      if (await metaFile.exists()) {
        await metaFile.writeAsString(jsonEncode(updated.toJson()), flush: true);
      }

      await _persistManifest();
    }
  }

  @override
  Future<void> renameDocument(String id, String newTitle) async {
    await _ensureInitialized();
    final index = _documentsCache.indexWhere((d) => d.id == id);
    if (index >= 0) {
      final doc = _documentsCache[index];
      final updated = doc.copyWith(
        title: newTitle.trim(),
        updatedAt: DateTime.now(),
      );
      _documentsCache[index] = updated;

      final metaFile = File('${_baseDir!.path}/$id/meta.json');
      if (await metaFile.exists()) {
        await metaFile.writeAsString(jsonEncode(updated.toJson()), flush: true);
      }

      await _persistManifest();
    }
  }

  @override
  Future<void> moveDocument(String id, String? folderId) async {
    await _ensureInitialized();
    final index = _documentsCache.indexWhere((d) => d.id == id);
    if (index >= 0) {
      final doc = _documentsCache[index];
      final updated = doc.copyWith(
        folderId: folderId,
        updatedAt: DateTime.now(),
      );
      _documentsCache[index] = updated;

      final metaFile = File('${_baseDir!.path}/$id/meta.json');
      if (await metaFile.exists()) {
        await metaFile.writeAsString(jsonEncode(updated.toJson()), flush: true);
      }

      await _persistManifest();
    }
  }

  @override
  Future<List<Folder>> getFolders() async {
    await _ensureInitialized();
    return List<Folder>.from(_foldersCache);
  }

  @override
  Future<void> createFolder(Folder folder) async {
    await _ensureInitialized();
    _foldersCache.add(folder);
    await _persistManifest();
  }

  @override
  Future<void> deleteFolder(String folderId) async {
    await _ensureInitialized();
    _foldersCache.removeWhere((f) => f.id == folderId);
    await _persistManifest();
  }
}
