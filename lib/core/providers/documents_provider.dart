import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../services/document_repository.dart';
import '../services/local_document_repository.dart';
import '../data/sample_data.dart';

enum DocumentFilter {
  all,
  pdfs,
  images,
  favorites,
}

enum DocumentViewMode {
  grid,
  list,
}

enum DocumentSort {
  recent,
  name,
  oldest,
}

/// Provider managing documents list, search, filters, sorting, view mode, and selection state.
class DocumentsProvider extends ChangeNotifier {
  final DocumentRepository _repository;

  List<Document> _documents = [];
  List<Folder> _folders = [];
  bool _isLoading = true;

  DocumentFilter _filter = DocumentFilter.all;
  DocumentViewMode _viewMode = DocumentViewMode.grid;
  DocumentSort _sort = DocumentSort.recent;
  String _searchQuery = '';

  // Selection mode
  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};

  DocumentsProvider({DocumentRepository? repository})
      : _repository = repository ?? LocalDocumentRepository.instance {
    loadData();
  }

  bool get isLoading => _isLoading;
  List<Document> get documents => _documents;
  List<Folder> get folders => _folders;
  DocumentFilter get filter => _filter;
  DocumentViewMode get viewMode => _viewMode;
  DocumentSort get sort => _sort;
  String get searchQuery => _searchQuery;
  bool get isSelectionMode => _isSelectionMode;
  Set<String> get selectedIds => _selectedIds;
  int get selectedCount => _selectedIds.length;

  List<Document> get recentDocuments {
    final list = List<Document>.from(_documents);
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list.take(5).toList();
  }

  List<Document> get filteredDocuments {
    var result = List<Document>.from(_documents);

    // Filter by type / favorite
    switch (_filter) {
      case DocumentFilter.all:
        break;
      case DocumentFilter.pdfs:
        result = result.where((d) => d.format == DocumentFormat.pdf).toList();
        break;
      case DocumentFilter.images:
        result = result.where((d) => d.format == DocumentFormat.image).toList();
        break;
      case DocumentFilter.favorites:
        result = result.where((d) => d.isFavorite).toList();
        break;
    }

    // Search query
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      result = result.where((d) {
        final titleMatch = d.title.toLowerCase().contains(q);
        final summaryMatch = d.ocrSummary?.toLowerCase().contains(q) ?? false;
        return titleMatch || summaryMatch;
      }).toList();
    }

    // Sort
    switch (_sort) {
      case DocumentSort.recent:
        result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        break;
      case DocumentSort.name:
        result.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case DocumentSort.oldest:
        result.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
    }

    return result;
  }

  Future<void> loadData() async {
    _isLoading = true;
    notifyListeners();

    _documents = await _repository.getAllDocuments();
    _folders = await _repository.getFolders();

    _isLoading = false;
    notifyListeners();
  }

  Document? getDocument(String id) {
    try {
      return _documents.firstWhere((d) => d.id == id);
    } catch (_) {
      return null;
    }
  }

  Folder? getFolder(String? id) {
    if (id == null) return null;
    try {
      return _folders.firstWhere((f) => f.id == id);
    } catch (_) {
      return null;
    }
  }

  void setFilter(DocumentFilter filter) {
    _filter = filter;
    notifyListeners();
  }

  void setViewMode(DocumentViewMode mode) {
    _viewMode = mode;
    notifyListeners();
  }

  void setSort(DocumentSort sort) {
    _sort = sort;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  // Selection mode
  void setSelectionMode(bool value) {
    _isSelectionMode = value;
    if (!value) {
      _selectedIds.clear();
    }
    notifyListeners();
  }

  void toggleSelect(String id) {
    if (_selectedIds.contains(id)) {
      _selectedIds.remove(id);
    } else {
      _selectedIds.add(id);
    }
    notifyListeners();
  }

  void selectAll() {
    _selectedIds.addAll(filteredDocuments.map((d) => d.id));
    notifyListeners();
  }

  void clearSelection() {
    _selectedIds.clear();
    notifyListeners();
  }

  // CRUD actions
  Future<void> addDocument(Document document) async {
    await _repository.saveDocument(document);
    await loadData();
  }

  Future<void> renameDocument(String id, String newTitle) async {
    await _repository.renameDocument(id, newTitle);
    await loadData();
  }

  Future<void> deleteDocument(String id) async {
    await _repository.deleteDocument(id);
    _selectedIds.remove(id);
    await loadData();
  }

  Future<void> deleteSelected() async {
    for (final id in _selectedIds.toList()) {
      await _repository.deleteDocument(id);
    }
    _selectedIds.clear();
    _isSelectionMode = false;
    await loadData();
  }

  Future<void> toggleFavorite(String id) async {
    await _repository.toggleFavorite(id);
    await loadData();
  }

  Future<void> moveDocument(String id, String? folderId) async {
    await _repository.moveDocument(id, folderId);
    await loadData();
  }

  Future<void> duplicateDocument(String id) async {
    final doc = getDocument(id);
    if (doc == null) return;

    final duplicated = doc.copyWith(
      id: 'doc-${DateTime.now().millisecondsSinceEpoch}',
      title: '${doc.title} (Copy)',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await addDocument(duplicated);
  }

  Future<void> createFolder(String name, {Color color = const Color(0xFF2563EB), IconData icon = Icons.folder_rounded}) async {
    final folder = Folder(
      id: 'folder-${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      color: color,
      icon: icon,
      createdAt: DateTime.now(),
    );
    await _repository.createFolder(folder);
    await loadData();
  }

  Future<void> deleteFolder(String folderId) async {
    await _repository.deleteFolder(folderId);
    // Unassign documents in this folder
    for (final doc in _documents.where((d) => d.folderId == folderId)) {
      await _repository.moveDocument(doc.id, null);
    }
    await loadData();
  }

  // Helpers to test empty and populated states
  void clearAllForEmptyPreview() {
    _documents.clear();
    notifyListeners();
  }

  void restoreSampleData() {
    _documents = SampleDocumentRepository.getInitialDocuments();
    _folders = List.from(SampleDocumentRepository.defaultFolders);
    notifyListeners();
  }
}
