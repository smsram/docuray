import '../../models/models.dart';

/// Document repository interface separating UI/state from data persistence.
abstract class DocumentRepository {
  Future<List<Document>> getAllDocuments();
  Future<Document?> getDocumentById(String id);
  Future<void> saveDocument(Document document);
  Future<void> deleteDocument(String id);
  Future<void> toggleFavorite(String id);
  Future<void> renameDocument(String id, String newTitle);
  Future<void> moveDocument(String id, String? folderId);
  Future<List<Folder>> getFolders();
  Future<void> createFolder(Folder folder);
  Future<void> deleteFolder(String folderId);
}
