import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/models.dart';
import 'local_document_repository.dart';

/// Conflict resolution strategy for restoring documents.
enum ConflictResolution {
  replace,
  keepBoth,
  skip,
}

/// Thrown when Wi-Fi only backup is enabled but Wi-Fi is unavailable.
class WifiRequiredException implements Exception {
  final String message;
  const WifiRequiredException([this.message = 'Wi-Fi connection is required by backup settings. Waiting for Wi-Fi.']);
  @override
  String toString() => message;
}

/// Metadata entry in the Drive backup manifest.
class DriveBackupEntry {
  final String id;
  final String title;
  final String drivePdfFileId;
  final String? drivePackageFileId;
  final String? driveMetaFileId;
  final String backupTimestamp;
  final int fileSize;
  final int pageCount;
  final String? md5Checksum;
  final int version;
  final String status;

  const DriveBackupEntry({
    required this.id,
    required this.title,
    required this.drivePdfFileId,
    this.drivePackageFileId,
    this.driveMetaFileId,
    required this.backupTimestamp,
    required this.fileSize,
    required this.pageCount,
    this.md5Checksum,
    this.version = 1,
    this.status = 'synced',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'drivePdfFileId': drivePdfFileId,
    if (drivePackageFileId != null) 'drivePackageFileId': drivePackageFileId,
    if (driveMetaFileId != null) 'driveMetaFileId': driveMetaFileId,
    'backupTimestamp': backupTimestamp,
    'fileSize': fileSize,
    'pageCount': pageCount,
    if (md5Checksum != null) 'md5Checksum': md5Checksum,
    'version': version,
    'status': status,
  };

  factory DriveBackupEntry.fromJson(Map<String, dynamic> json) {
    return DriveBackupEntry(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Untitled',
      drivePdfFileId: json['drivePdfFileId'] as String,
      drivePackageFileId: json['drivePackageFileId'] as String?,
      driveMetaFileId: json['driveMetaFileId'] as String?,
      backupTimestamp: json['backupTimestamp'] as String? ?? '',
      fileSize: (json['fileSize'] as num?)?.toInt() ?? 0,
      pageCount: (json['pageCount'] as num?)?.toInt() ?? 1,
      md5Checksum: json['md5Checksum'] as String?,
      version: (json['version'] as num?)?.toInt() ?? 1,
      status: json['status'] as String? ?? 'synced',
    );
  }
}

/// Progress callback for backup/restore operations.
typedef BackupProgressCallback = void Function(int current, int total, String statusMessage);

/// Complete Google Drive Backup & Restore Service.
class GoogleDriveService {
  static final GoogleDriveService instance = GoogleDriveService._internal();

  GoogleDriveService._internal();

  static const String _folderNameBackups = 'DocuRay Backups';
  static const String _folderNameDocuments = 'Documents';
  static const String _folderNamePackages = 'Packages';
  static const String _folderNameMetadata = 'Metadata';
  static const String _manifestFileName = 'backup_manifest.json';

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      drive.DriveApi.driveFileScope,
      drive.DriveApi.driveAppdataScope,
    ],
  );

  drive.DriveApi? _driveApi;
  bool _isBackingUp = false;
  bool _isRestoring = false;

  bool get isBackingUp => _isBackingUp;
  bool get isRestoring => _isRestoring;
  bool get isSignedIn => _googleSignIn.currentUser != null;
  String? get currentUserEmail => _googleSignIn.currentUser?.email;

  /// Checks if active connection is Wi-Fi.
  Future<bool> isWifiAvailable() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.contains(ConnectivityResult.wifi);
    } catch (_) {
      return false;
    }
  }

  /// Silently attempts to sign in existing user on app launch.
  Future<bool> initSilentSignIn() async {
    try {
      final account = await _googleSignIn.signInSilently();
      if (account != null) {
        await _obtainDriveApi();
        return true;
      }
    } catch (e) {
      debugPrint('[DocuRay Drive] Silent sign in skipped or failed: $e');
    }
    return false;
  }

  /// Explicit user sign-in flow.
  Future<GoogleSignInAccount?> signIn() async {
    try {
      final account = await _googleSignIn.signIn();
      if (account != null) {
        await _obtainDriveApi();
      }
      return account;
    } catch (e) {
      debugPrint('[DocuRay Drive] Sign in error: $e');
      rethrow;
    }
  }

  /// Sign out without revoking permissions.
  Future<void> signOut() async {
    _driveApi = null;
    await _googleSignIn.signOut();
  }

  /// Disconnect and revoke Drive permissions.
  Future<void> disconnect() async {
    _driveApi = null;
    try {
      await _googleSignIn.disconnect();
    } catch (_) {
      await _googleSignIn.signOut();
    }
  }

  Future<drive.DriveApi> _obtainDriveApi() async {
    if (_driveApi != null) return _driveApi!;
    final authClient = await _googleSignIn.authenticatedClient();
    if (authClient == null) {
      throw const SocketException('User is not authenticated with Google.');
    }
    _driveApi = drive.DriveApi(authClient);
    return _driveApi!;
  }

  /// Finds an existing folder or creates it under [parentId] (or root if null).
  Future<String> _findOrCreateFolder(drive.DriveApi api, String folderName, {String? parentId}) async {
    final query = parentId == null
        ? "mimeType = 'application/vnd.google-apps.folder' and name = '$folderName' and trashed = false"
        : "mimeType = 'application/vnd.google-apps.folder' and name = '$folderName' and '$parentId' in parents and trashed = false";

    final list = await api.files.list(
      q: query,
      spaces: 'drive',
      $fields: 'files(id, name)',
    );

    if (list.files != null && list.files!.isNotEmpty) {
      return list.files!.first.id!;
    }

    // Create new folder
    final folderMetadata = drive.File()
      ..name = folderName
      ..mimeType = 'application/vnd.google-apps.folder'
      ..parents = parentId != null ? [parentId] : null;

    final created = await api.files.create(
      folderMetadata,
      $fields: 'id',
    );
    return created.id!;
  }

  /// Reads the backup manifest from the "DocuRay Backups" folder.
  Future<Map<String, DriveBackupEntry>> fetchBackupManifest() async {
    final api = await _obtainDriveApi();
    final backupFolderId = await _findOrCreateFolder(api, _folderNameBackups);

    final list = await api.files.list(
      q: "name = '$_manifestFileName' and '$backupFolderId' in parents and trashed = false",
      spaces: 'drive',
      $fields: 'files(id, name)',
    );

    if (list.files == null || list.files!.isEmpty) {
      return {};
    }

    final manifestFileId = list.files!.first.id!;
    final media = await api.files.get(
      manifestFileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;

    final bytes = <int>[];
    await for (final chunk in media.stream) {
      bytes.addAll(chunk);
    }

    final jsonStr = utf8.decode(bytes);
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    final docsList = data['documents'] as List<dynamic>? ?? [];

    final result = <String, DriveBackupEntry>{};
    for (final item in docsList) {
      final entry = DriveBackupEntry.fromJson(item as Map<String, dynamic>);
      result[entry.id] = entry;
    }
    return result;
  }

  /// Saves the backup manifest to the "DocuRay Backups" folder.
  Future<void> _saveBackupManifest(
    drive.DriveApi api,
    String backupFolderId,
    Map<String, DriveBackupEntry> entries,
  ) async {
    final data = {
      'version': 1,
      'lastBackup': DateTime.now().toIso8601String(),
      'documents': entries.values.map((e) => e.toJson()).toList(),
    };
    final jsonBytes = utf8.encode(jsonEncode(data));
    final mediaStream = Stream<List<int>>.value(jsonBytes);
    final media = drive.Media(mediaStream, jsonBytes.length);

    // Check if manifest already exists
    final list = await api.files.list(
      q: "name = '$_manifestFileName' and '$backupFolderId' in parents and trashed = false",
      spaces: 'drive',
      $fields: 'files(id)',
    );

    if (list.files != null && list.files!.isNotEmpty) {
      // Update existing manifest
      await api.files.update(
        drive.File(),
        list.files!.first.id!,
        uploadMedia: media,
      );
    } else {
      // Create new manifest
      final fileMetadata = drive.File()
        ..name = _manifestFileName
        ..parents = [backupFolderId]
        ..mimeType = 'application/json';

      await api.files.create(
        fileMetadata,
        uploadMedia: media,
      );
    }
  }

  /// Packages a complete document bundle (page images + metadata + pdf) into a zip file.
  Future<File?> _createDocumentBundle(Document doc) async {
    try {
      final archive = Archive();

      final pageMappings = <Map<String, dynamic>>[];
      for (int i = 0; i < doc.pages.length; i++) {
        final page = doc.pages[i];
        String? procArchiveName;
        String? origArchiveName;

        if (page.processedImagePath != null) {
          final procFile = File(page.processedImagePath!);
          if (await procFile.exists() && await procFile.length() > 0) {
            final bytes = await procFile.readAsBytes();
            procArchiveName = 'page_${i}_proc.jpg';
            archive.addFile(ArchiveFile(procArchiveName, bytes.length, bytes));
          }
        }

        if (page.originalImagePath != null) {
          final origFile = File(page.originalImagePath!);
          if (await origFile.exists() && await origFile.length() > 0) {
            final bytes = await origFile.readAsBytes();
            origArchiveName = 'page_${i}_orig.jpg';
            archive.addFile(ArchiveFile(origArchiveName, bytes.length, bytes));
          }
        }

        final pageJson = page.toJson();
        pageJson['procFileName'] = procArchiveName;
        pageJson['origFileName'] = origArchiveName;
        pageMappings.add(pageJson);
      }

      if (doc.pdfPath != null) {
        final pdfFile = File(doc.pdfPath!);
        if (await pdfFile.exists() && await pdfFile.length() > 0) {
          final bytes = await pdfFile.readAsBytes();
          archive.addFile(ArchiveFile('document.pdf', bytes.length, bytes));
        }
      }

      final bundleMeta = {
        'id': doc.id,
        'title': doc.title,
        'createdAt': doc.createdAt.toIso8601String(),
        'updatedAt': doc.updatedAt.toIso8601String(),
        'folderId': doc.folderId,
        'isFavorite': doc.isFavorite,
        'pageCount': doc.pageCount,
        'pages': pageMappings,
        'rawDocumentJson': doc.toJson(),
      };
      final metaBytes = utf8.encode(jsonEncode(bundleMeta));
      archive.addFile(ArchiveFile('metadata.json', metaBytes.length, metaBytes));

      final zipEncoder = ZipEncoder();
      final zipData = zipEncoder.encode(archive);
      final tempDir = await getTemporaryDirectory();
      final bundleFile = File('${tempDir.path}/bundle_${doc.id}_${DateTime.now().millisecondsSinceEpoch}.zip');
      await bundleFile.writeAsBytes(zipData);
      return bundleFile;
    } catch (e) {
      debugPrint('[DocuRay Drive] Error creating document bundle: $e');
      return null;
    }
  }

  /// Backs up all local documents to Google Drive.
  /// Prevents duplicates by updating existing files in Drive.
  Future<int> backupAllDocuments({
    bool wifiOnly = false,
    bool includeMetadata = true,
    BackupProgressCallback? onProgress,
  }) async {
    if (_isBackingUp) {
      throw StateError('A backup operation is already in progress.');
    }

    if (wifiOnly) {
      final onWifi = await isWifiAvailable();
      if (!onWifi) {
        throw const WifiRequiredException();
      }
    }

    _isBackingUp = true;

    try {
      final api = await _obtainDriveApi();
      onProgress?.call(0, 0, 'Connecting to Google Drive...');

      // Find or create folder hierarchy
      final backupFolderId = await _findOrCreateFolder(api, _folderNameBackups);
      final documentsFolderId = await _findOrCreateFolder(api, _folderNameDocuments, parentId: backupFolderId);
      final packagesFolderId = await _findOrCreateFolder(api, _folderNamePackages, parentId: backupFolderId);
      final metadataFolderId = includeMetadata
          ? await _findOrCreateFolder(api, _folderNameMetadata, parentId: backupFolderId)
          : null;

      // Load existing manifest
      final manifestEntries = await fetchBackupManifest();

      // Get local documents
      final localDocs = await LocalDocumentRepository.instance.getAllDocuments();
      final total = localDocs.length;
      int successCount = 0;

      for (int i = 0; i < total; i++) {
        // Check Wi-Fi before each document upload if wifiOnly is active
        if (wifiOnly) {
          final onWifi = await isWifiAvailable();
          if (!onWifi) {
            throw const WifiRequiredException('Wi-Fi connection lost during backup. Upload paused.');
          }
        }

        final doc = localDocs[i];
        onProgress?.call(i + 1, total, 'Backing up "${doc.title}" (${i + 1}/$total)...');

        if (doc.pdfPath == null || !File(doc.pdfPath!).existsSync()) {
          continue;
        }

        final pdfFile = File(doc.pdfPath!);
        final pdfBytes = await pdfFile.readAsBytes();
        final checksum = md5.convert(pdfBytes).toString();
        final safeName = '${doc.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}.pdf';

        String drivePdfId;
        final existingEntry = manifestEntries[doc.id];

        if (existingEntry != null) {
          // Update existing PDF in Drive
          try {
            final media = drive.Media(pdfFile.openRead(), pdfBytes.length);
            final updateMeta = drive.File()..name = safeName;
            final updated = await api.files.update(
              updateMeta,
              existingEntry.drivePdfFileId,
              uploadMedia: media,
              $fields: 'id',
            );
            drivePdfId = updated.id ?? existingEntry.drivePdfFileId;
          } catch (e) {
            // If file was deleted from Drive, recreate it
            final media = drive.Media(pdfFile.openRead(), pdfBytes.length);
            final newMeta = drive.File()
              ..name = safeName
              ..parents = [documentsFolderId]
              ..mimeType = 'application/pdf';
            final created = await api.files.create(newMeta, uploadMedia: media, $fields: 'id');
            drivePdfId = created.id!;
          }
        } else {
          // Upload new PDF to Drive
          final media = drive.Media(pdfFile.openRead(), pdfBytes.length);
          final newMeta = drive.File()
            ..name = safeName
            ..parents = [documentsFolderId]
            ..mimeType = 'application/pdf';
          final created = await api.files.create(newMeta, uploadMedia: media, $fields: 'id');
          drivePdfId = created.id!;
        }

        // Upload/Update metadata JSON if enabled
        String? driveMetaId;
        if (includeMetadata && metadataFolderId != null) {
          final metaJson = jsonEncode(doc.toJson());
          final metaBytes = utf8.encode(metaJson);
          final metaStream = Stream<List<int>>.value(metaBytes);
          final metaMedia = drive.Media(metaStream, metaBytes.length);
          final metaName = '${doc.id}_meta.json';

          if (existingEntry?.driveMetaFileId != null) {
            try {
              final updatedMeta = await api.files.update(
                drive.File()..name = metaName,
                existingEntry!.driveMetaFileId!,
                uploadMedia: metaMedia,
                $fields: 'id',
              );
              driveMetaId = updatedMeta.id ?? existingEntry.driveMetaFileId;
            } catch (_) {
              final createdMeta = await api.files.create(
                drive.File()
                  ..name = metaName
                  ..parents = [metadataFolderId]
                  ..mimeType = 'application/json',
                uploadMedia: metaMedia,
                $fields: 'id',
              );
              driveMetaId = createdMeta.id;
            }
          } else {
            final createdMeta = await api.files.create(
              drive.File()
                ..name = metaName
                ..parents = [metadataFolderId]
                ..mimeType = 'application/json',
              uploadMedia: metaMedia,
              $fields: 'id',
            );
            driveMetaId = createdMeta.id;
          }
        }

        // Upload/Update complete document bundle (page images + metadata + PDF)
        String? drivePackageId;
        try {
          final bundleFile = await _createDocumentBundle(doc);
          if (bundleFile != null && await bundleFile.exists()) {
            final bundleBytes = await bundleFile.readAsBytes();
            final bundleName = '${doc.id}_bundle.zip';
            final bundleMedia = drive.Media(bundleFile.openRead(), bundleBytes.length);

            if (existingEntry?.drivePackageFileId != null) {
              try {
                final updated = await api.files.update(
                  drive.File()..name = bundleName,
                  existingEntry!.drivePackageFileId!,
                  uploadMedia: bundleMedia,
                  $fields: 'id',
                );
                drivePackageId = updated.id ?? existingEntry.drivePackageFileId;
              } catch (_) {
                final created = await api.files.create(
                  drive.File()
                    ..name = bundleName
                    ..parents = [packagesFolderId]
                    ..mimeType = 'application/zip',
                  uploadMedia: bundleMedia,
                  $fields: 'id',
                );
                drivePackageId = created.id;
              }
            } else {
              final created = await api.files.create(
                drive.File()
                  ..name = bundleName
                  ..parents = [packagesFolderId]
                  ..mimeType = 'application/zip',
                uploadMedia: bundleMedia,
                $fields: 'id',
              );
              drivePackageId = created.id;
            }

            try {
              await bundleFile.delete();
            } catch (_) {}
          }
        } catch (e) {
          debugPrint('[DocuRay Drive] Bundle packaging error for "${doc.title}": $e');
        }

        // Record in manifest
        manifestEntries[doc.id] = DriveBackupEntry(
          id: doc.id,
          title: doc.title,
          drivePdfFileId: drivePdfId,
          drivePackageFileId: drivePackageId ?? existingEntry?.drivePackageFileId,
          driveMetaFileId: driveMetaId,
          backupTimestamp: DateTime.now().toIso8601String(),
          fileSize: pdfBytes.length,
          pageCount: doc.pages.length,
          md5Checksum: checksum,
          version: 1,
          status: 'synced',
        );

        // Update local sync metadata
        final updatedDoc = doc.copyWith(
          syncMetadata: SyncMetadata(
            status: SyncStatus.synced,
            lastSyncedAt: DateTime.now(),
            driveFileId: drivePdfId,
          ),
        );
        await LocalDocumentRepository.instance.saveDocument(updatedDoc);
        successCount++;
      }

      // Save updated manifest
      onProgress?.call(total, total, 'Updating backup manifest...');
      await _saveBackupManifest(api, backupFolderId, manifestEntries);
      onProgress?.call(total, total, 'Backup complete! ($successCount documents backed up)');
      return successCount;
    } finally {
      _isBackingUp = false;
    }
  }

  /// Asynchronously backs up a single document (for auto-backup).
  Future<bool> backupSingleDocument(
    Document doc, {
    bool wifiOnly = false,
    bool includeMetadata = true,
  }) async {
    if (_isBackingUp || !isSignedIn) return false;

    if (wifiOnly) {
      final onWifi = await isWifiAvailable();
      if (!onWifi) {
        debugPrint('[DocuRay Drive] Auto-backup skipped: waiting for Wi-Fi.');
        return false;
      }
    }

    if (doc.pdfPath == null || !File(doc.pdfPath!).existsSync()) {
      return false;
    }

    try {
      final api = await _obtainDriveApi();
      final backupFolderId = await _findOrCreateFolder(api, _folderNameBackups);
      final documentsFolderId = await _findOrCreateFolder(api, _folderNameDocuments, parentId: backupFolderId);
      final packagesFolderId = await _findOrCreateFolder(api, _folderNamePackages, parentId: backupFolderId);
      final metadataFolderId = includeMetadata
          ? await _findOrCreateFolder(api, _folderNameMetadata, parentId: backupFolderId)
          : null;

      final manifestEntries = await fetchBackupManifest();

      final pdfFile = File(doc.pdfPath!);
      final pdfBytes = await pdfFile.readAsBytes();
      final checksum = md5.convert(pdfBytes).toString();
      final safeName = '${doc.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}.pdf';

      String drivePdfId;
      final existingEntry = manifestEntries[doc.id];

      if (existingEntry != null) {
        try {
          final media = drive.Media(pdfFile.openRead(), pdfBytes.length);
          final updated = await api.files.update(
            drive.File()..name = safeName,
            existingEntry.drivePdfFileId,
            uploadMedia: media,
            $fields: 'id',
          );
          drivePdfId = updated.id ?? existingEntry.drivePdfFileId;
        } catch (_) {
          final media = drive.Media(pdfFile.openRead(), pdfBytes.length);
          final created = await api.files.create(
            drive.File()
              ..name = safeName
              ..parents = [documentsFolderId]
              ..mimeType = 'application/pdf',
            uploadMedia: media,
            $fields: 'id',
          );
          drivePdfId = created.id!;
        }
      } else {
        final media = drive.Media(pdfFile.openRead(), pdfBytes.length);
        final created = await api.files.create(
          drive.File()
            ..name = safeName
            ..parents = [documentsFolderId]
            ..mimeType = 'application/pdf',
          uploadMedia: media,
          $fields: 'id',
        );
        drivePdfId = created.id!;
      }

      String? driveMetaId;
      if (includeMetadata && metadataFolderId != null) {
        final metaJson = jsonEncode(doc.toJson());
        final metaBytes = utf8.encode(metaJson);
        final metaStream = Stream<List<int>>.value(metaBytes);
        final metaMedia = drive.Media(metaStream, metaBytes.length);
        final metaName = '${doc.id}_meta.json';

        if (existingEntry?.driveMetaFileId != null) {
          try {
            final updatedMeta = await api.files.update(
              drive.File()..name = metaName,
              existingEntry!.driveMetaFileId!,
              uploadMedia: metaMedia,
              $fields: 'id',
            );
            driveMetaId = updatedMeta.id ?? existingEntry.driveMetaFileId;
          } catch (_) {
            final createdMeta = await api.files.create(
              drive.File()
                ..name = metaName
                ..parents = [metadataFolderId]
                ..mimeType = 'application/json',
              uploadMedia: metaMedia,
              $fields: 'id',
            );
            driveMetaId = createdMeta.id;
          }
        } else {
          final createdMeta = await api.files.create(
            drive.File()
              ..name = metaName
              ..parents = [metadataFolderId]
              ..mimeType = 'application/json',
            uploadMedia: metaMedia,
            $fields: 'id',
          );
          driveMetaId = createdMeta.id;
        }
      }

      // Upload/Update complete document bundle (page images + metadata + PDF)
      String? drivePackageId;
      try {
        final bundleFile = await _createDocumentBundle(doc);
        if (bundleFile != null && await bundleFile.exists()) {
          final bundleBytes = await bundleFile.readAsBytes();
          final bundleName = '${doc.id}_bundle.zip';
          final bundleMedia = drive.Media(bundleFile.openRead(), bundleBytes.length);

          if (existingEntry?.drivePackageFileId != null) {
            try {
              final updated = await api.files.update(
                drive.File()..name = bundleName,
                existingEntry!.drivePackageFileId!,
                uploadMedia: bundleMedia,
                $fields: 'id',
              );
              drivePackageId = updated.id ?? existingEntry.drivePackageFileId;
            } catch (_) {
              final created = await api.files.create(
                drive.File()
                  ..name = bundleName
                  ..parents = [packagesFolderId]
                  ..mimeType = 'application/zip',
                uploadMedia: bundleMedia,
                $fields: 'id',
              );
              drivePackageId = created.id;
            }
          } else {
            final created = await api.files.create(
              drive.File()
                ..name = bundleName
                ..parents = [packagesFolderId]
                ..mimeType = 'application/zip',
              uploadMedia: bundleMedia,
              $fields: 'id',
            );
            drivePackageId = created.id;
          }

          try {
            await bundleFile.delete();
          } catch (_) {}
        }
      } catch (e) {
        debugPrint('[DocuRay Drive] Auto-backup bundle error for "${doc.title}": $e');
      }

      manifestEntries[doc.id] = DriveBackupEntry(
        id: doc.id,
        title: doc.title,
        drivePdfFileId: drivePdfId,
        drivePackageFileId: drivePackageId ?? existingEntry?.drivePackageFileId,
        driveMetaFileId: driveMetaId,
        backupTimestamp: DateTime.now().toIso8601String(),
        fileSize: pdfBytes.length,
        pageCount: doc.pages.length,
        md5Checksum: checksum,
        version: 1,
        status: 'synced',
      );

      await _saveBackupManifest(api, backupFolderId, manifestEntries);

      final updatedDoc = doc.copyWith(
        syncMetadata: SyncMetadata(
          status: SyncStatus.synced,
          lastSyncedAt: DateTime.now(),
          driveFileId: drivePdfId,
        ),
      );
      await LocalDocumentRepository.instance.saveDocument(updatedDoc);
      return true;
    } catch (e) {
      debugPrint('[DocuRay Drive] Auto-backup failed for ${doc.title}: $e');
      return false;
    }
  }

  /// Restores a selected document from Google Drive.
  /// Supports replace, keepBoth, and skip conflict resolutions.
  /// Verifies checksums and preserves local document safety.
  Future<Document?> restoreDocument(
    DriveBackupEntry entry, {
    ConflictResolution resolution = ConflictResolution.keepBoth,
    BackupProgressCallback? onProgress,
  }) async {
    if (_isRestoring) {
      throw StateError('A restore operation is already in progress.');
    }
    _isRestoring = true;

    try {
      final api = await _obtainDriveApi();
      onProgress?.call(0, 1, 'Restoring "${entry.title}"...');

      final localRepo = LocalDocumentRepository.instance;
      final existingDoc = await localRepo.getDocumentById(entry.id);

      if (existingDoc != null && resolution == ConflictResolution.skip) {
        onProgress?.call(1, 1, 'Skipped "${entry.title}" (already exists).');
        return null;
      }

      final isReplacing = (existingDoc != null && resolution == ConflictResolution.replace);
      final isCopy = (existingDoc != null && resolution == ConflictResolution.keepBoth);

      final targetId = isCopy
          ? 'doc_${DateTime.now().millisecondsSinceEpoch}_restored'
          : entry.id;

      final targetTitle = isCopy
          ? '${entry.title} (Restored)'
          : entry.title;

      final appDir = await getApplicationDocumentsDirectory();
      final docDir = Directory('${appDir.path}/documents/$targetId');
      if (!await docDir.exists()) {
        await docDir.create(recursive: true);
      }

      // Download PDF to temporary file first for atomic verification
      final tempFileName = 'temp_download_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final tempFile = File('${docDir.path}/$tempFileName');

      final media = await api.files.get(
        entry.drivePdfFileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      final sink = tempFile.openWrite();
      await for (final chunk in media.stream) {
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();

      // 1. Verify file size
      final downloadedSize = await tempFile.length();
      if (downloadedSize == 0) {
        if (await tempFile.exists()) await tempFile.delete();
        throw FileSystemException('Downloaded PDF file is empty.', tempFile.path);
      }

      // 2. Verify MD5 Checksum
      final downloadedBytes = await tempFile.readAsBytes();
      final computedMd5 = md5.convert(downloadedBytes).toString();
      if (entry.md5Checksum != null &&
          entry.md5Checksum!.isNotEmpty &&
          computedMd5.toLowerCase() != entry.md5Checksum!.toLowerCase()) {
        if (await tempFile.exists()) await tempFile.delete();
        throw Exception('Checksum verification failed for "${entry.title}". Downloaded file corrupted.');
      }

      // 3. Move verified temp file into place with recovery backup if replacing
      final safeFileName = targetTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final targetPdfPath = '${docDir.path}/$safeFileName.pdf';
      final targetFile = File(targetPdfPath);

      File? recoveryBackupFile;
      if (isReplacing && await targetFile.exists()) {
        final recoveryPath = '${docDir.path}/backup_recovery_${DateTime.now().millisecondsSinceEpoch}.pdf';
        recoveryBackupFile = await targetFile.copy(recoveryPath);
      }

      try {
        await tempFile.copy(targetPdfPath);
        if (await tempFile.exists()) await tempFile.delete();
        // Delete recovery backup once replacement succeeds
        if (recoveryBackupFile != null && await recoveryBackupFile.exists()) {
          await recoveryBackupFile.delete();
        }
      } catch (e) {
        // If replacement failed, restore recovery backup
        if (recoveryBackupFile != null && await recoveryBackupFile.exists()) {
          await recoveryBackupFile.copy(targetPdfPath);
          await recoveryBackupFile.delete();
        }
        rethrow;
      }

      // 4. Download and unpack document bundle if available (page images + metadata)
      List<DocumentPage>? restoredPages;
      Map<String, dynamic>? bundleMeta;

      if (entry.drivePackageFileId != null && entry.drivePackageFileId!.isNotEmpty) {
        onProgress?.call(0, 1, 'Restoring page images for "${entry.title}"...');
        final tempBundleFile = File('${docDir.path}/temp_bundle_${DateTime.now().millisecondsSinceEpoch}.zip');
        try {
          final bundleMedia = await api.files.get(
            entry.drivePackageFileId!,
            downloadOptions: drive.DownloadOptions.fullMedia,
          ) as drive.Media;

          final bundleSink = tempBundleFile.openWrite();
          await for (final chunk in bundleMedia.stream) {
            bundleSink.add(chunk);
          }
          await bundleSink.flush();
          await bundleSink.close();

          if (await tempBundleFile.exists() && await tempBundleFile.length() > 0) {
            final bundleBytes = await tempBundleFile.readAsBytes();
            final archive = ZipDecoder().decodeBytes(bundleBytes);

            for (final file in archive.files) {
              if (file.isFile) {
                if (file.name == 'metadata.json') {
                  final metaStr = utf8.decode(file.content as List<int>);
                  bundleMeta = jsonDecode(metaStr) as Map<String, dynamic>?;
                } else if (file.name.endsWith('.jpg') || file.name.endsWith('.png') || file.name.endsWith('.jpeg')) {
                  final imgFile = File('${docDir.path}/${file.name}');
                  await imgFile.writeAsBytes(file.content as List<int>);
                }
              }
            }

            // If metadata.json was in bundle, map pages to verified local disk images
            if (bundleMeta != null && bundleMeta['pages'] is List) {
              final pagesJsonList = bundleMeta['pages'] as List<dynamic>;
              final pages = <DocumentPage>[];
              for (int idx = 0; idx < pagesJsonList.length; idx++) {
                final pMap = Map<String, dynamic>.from(pagesJsonList[idx] as Map);
                final procFileName = pMap['procFileName'] as String?;
                final origFileName = pMap['origFileName'] as String?;

                String? procPath;
                if (procFileName != null) {
                  final f = File('${docDir.path}/$procFileName');
                  if (await f.exists() && await f.length() > 0) {
                    procPath = f.path;
                  }
                }

                String? origPath;
                if (origFileName != null) {
                  final f = File('${docDir.path}/$origFileName');
                  if (await f.exists() && await f.length() > 0) {
                    origPath = f.path;
                  }
                }

                if (procPath != null) {
                  pMap['id'] = '${targetId}_p${idx + 1}';
                  pMap['pageNumber'] = idx + 1;
                  pMap['processedImagePath'] = procPath;
                  pMap['originalImagePath'] = origPath;
                  pages.add(DocumentPage.fromJson(pMap));
                }
              }
              if (pages.isNotEmpty) {
                restoredPages = pages;
              }
            }
          }
        } catch (e) {
          debugPrint('[DocuRay Drive] Failed to unpack package bundle: $e');
        } finally {
          if (await tempBundleFile.exists()) {
            try {
              await tempBundleFile.delete();
            } catch (_) {}
          }
        }
      }

      // 5. Construct restored Document
      Document? restoredDoc;

      if (bundleMeta != null) {
        try {
          final rawJson = bundleMeta['rawDocumentJson'] as Map<String, dynamic>?;
          if (rawJson != null) {
            final parsed = Document.fromJson(rawJson);
            restoredDoc = parsed.copyWith(
              id: targetId,
              title: targetTitle,
              pdfPath: targetPdfPath,
              fileSizeBytes: downloadedSize,
              updatedAt: DateTime.now(),
              pages: restoredPages ?? parsed.pages,
              syncMetadata: SyncMetadata(
                status: SyncStatus.synced,
                lastSyncedAt: DateTime.now(),
                driveFileId: entry.drivePdfFileId,
              ),
            );
          }
        } catch (_) {}
      }

      if (restoredDoc == null && entry.driveMetaFileId != null) {
        try {
          final metaMedia = await api.files.get(
            entry.driveMetaFileId!,
            downloadOptions: drive.DownloadOptions.fullMedia,
          ) as drive.Media;

          final metaBytes = <int>[];
          await for (final chunk in metaMedia.stream) {
            metaBytes.addAll(chunk);
          }
          final metaJson = jsonDecode(utf8.decode(metaBytes)) as Map<String, dynamic>;
          final parsed = Document.fromJson(metaJson);

          restoredDoc = parsed.copyWith(
            id: targetId,
            title: targetTitle,
            pdfPath: targetPdfPath,
            fileSizeBytes: downloadedSize,
            updatedAt: DateTime.now(),
            pages: restoredPages ?? parsed.pages,
            syncMetadata: SyncMetadata(
              status: SyncStatus.synced,
              lastSyncedAt: DateTime.now(),
              driveFileId: entry.drivePdfFileId,
            ),
          );
        } catch (e) {
          debugPrint('[DocuRay Drive] Metadata download fallback: $e');
        }
      }

      // Fallback if legacy backup or metadata missing
      if (restoredDoc == null) {
        if (restoredPages != null && restoredPages.isNotEmpty) {
          restoredDoc = Document(
            id: targetId,
            title: targetTitle,
            pages: restoredPages,
            createdAt: DateTime.tryParse(entry.backupTimestamp) ?? DateTime.now(),
            updatedAt: DateTime.now(),
            pdfPath: targetPdfPath,
            fileSizeBytes: downloadedSize,
            syncMetadata: SyncMetadata(
              status: SyncStatus.synced,
              lastSyncedAt: DateTime.now(),
              driveFileId: entry.drivePdfFileId,
            ),
          );
        } else {
          // Legacy PDF-only backup fallback
          debugPrint('[DocuRay Drive] Restoring legacy backup without bundled page images.');
          restoredDoc = Document(
            id: targetId,
            title: targetTitle,
            pages: List.generate(
              entry.pageCount > 0 ? entry.pageCount : 1,
              (idx) => DocumentPage(
                id: '${targetId}_p${idx + 1}',
                pageNumber: idx + 1,
                processedImagePath: targetPdfPath,
              ),
            ),
            createdAt: DateTime.tryParse(entry.backupTimestamp) ?? DateTime.now(),
            updatedAt: DateTime.now(),
            pdfPath: targetPdfPath,
            fileSizeBytes: downloadedSize,
            syncMetadata: SyncMetadata(
              status: SyncStatus.synced,
              lastSyncedAt: DateTime.now(),
              driveFileId: entry.drivePdfFileId,
            ),
          );
        }
      }

      // Verify all page image files exist on disk with non-zero size
      for (final page in restoredDoc.pages) {
        if (page.processedImagePath != null) {
          final f = File(page.processedImagePath!);
          if (!await f.exists() || await f.length() == 0) {
            debugPrint('[DocuRay Drive] Warning: restored page image file missing or empty: ${page.processedImagePath}');
          }
        }
      }

      await localRepo.saveDocument(restoredDoc);
      onProgress?.call(1, 1, 'Restored "$targetTitle" successfully.');
      return restoredDoc;
    } finally {
      _isRestoring = false;
    }
  }
}
