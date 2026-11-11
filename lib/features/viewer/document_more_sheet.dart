import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/widgets/bottom_action_sheet.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/providers/documents_provider.dart';
import '../../models/models.dart';
import '../share/share_export_sheet.dart';

/// Screen 8: Document More Menu Action Sheet with Rename, Move, Favorite, Duplicate, Export, Share, Drive, and Delete.
class DocumentMoreSheet {
  static void show(
    BuildContext context, {
    required Document document,
    required DocumentsProvider provider,
    required VoidCallback onDeleted,
    required VoidCallback onRenamed,
  }) {
    BottomActionSheet.show(
      context: context,
      title: document.title,
      items: [
        // 1. Rename
        ActionSheetItem(
          title: 'Rename document',
          icon: Icons.edit_outlined,
          onTap: () => _showRenameDialog(context, document, provider, onRenamed),
        ),
        // 2. Favorite / Unfavorite
        ActionSheetItem(
          title: document.isFavorite ? 'Remove from favorites' : 'Add to favorites',
          icon: document.isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
          iconColor: document.isFavorite ? AppColors.favoriteYellow : null,
          onTap: () => provider.toggleFavorite(document.id),
        ),
        // 3. Move to folder
        ActionSheetItem(
          title: 'Move to folder',
          icon: Icons.drive_file_move_outlined,
          onTap: () => _showMoveDialog(context, document, provider),
        ),
        // 4. Duplicate
        ActionSheetItem(
          title: 'Duplicate document',
          icon: Icons.content_copy_rounded,
          onTap: () async {
            await provider.duplicateDocument(document.id);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Document duplicated.')),
              );
            }
          },
        ),
        // 5. Export / Share
        ActionSheetItem(
          title: 'Share & Export',
          icon: Icons.share_outlined,
          onTap: () {
            ShareExportSheet.show(context, documentTitle: document.title);
          },
        ),
        // 6. Back up to Google Drive
        ActionSheetItem(
          title: 'Back up to Google Drive',
          subtitle: document.syncMetadata.status == SyncStatus.synced ? 'Synced' : 'Ready to upload',
          icon: Icons.cloud_upload_outlined,
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Backing up "${document.title}" to Google Drive...'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
        ),
        // 7. Delete
        ActionSheetItem(
          title: 'Delete document',
          icon: Icons.delete_outline_rounded,
          isDestructive: true,
          onTap: () async {
            final confirm = await ConfirmDialog.show(
              context,
              title: 'Delete document?',
              message: 'This document and its ${document.pageCount} ${document.pageCount == 1 ? 'page' : 'pages'} will be permanently removed.',
              confirmLabel: 'Delete',
              isDestructive: true,
            );
            if (confirm == true) {
              await provider.deleteDocument(document.id);
              onDeleted();
            }
          },
        ),
      ],
    );
  }

  static void _showRenameDialog(
    BuildContext context,
    Document document,
    DocumentsProvider provider,
    VoidCallback onRenamed,
  ) {
    final controller = TextEditingController(text: document.title);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: AppDimensions.borderCard),
        title: const Text('Rename document'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Document title',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                provider.renameDocument(document.id, newName);
                onRenamed();
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  static void _showMoveDialog(
    BuildContext context,
    Document document,
    DocumentsProvider provider,
  ) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: AppDimensions.borderSheet),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text('Move to folder', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                ),
                ListTile(
                  leading: const Icon(Icons.folder_off_outlined),
                  title: const Text('No folder (Root)'),
                  trailing: document.folderId == null ? const Icon(Icons.check_rounded, color: AppColors.primary) : null,
                  onTap: () {
                    provider.moveDocument(document.id, null);
                    Navigator.pop(ctx);
                  },
                ),
                ...provider.folders.map(
                  (f) => ListTile(
                    leading: Icon(f.icon, color: f.color),
                    title: Text(f.name),
                    trailing: document.folderId == f.id ? const Icon(Icons.check_rounded, color: AppColors.primary) : null,
                    onTap: () {
                      provider.moveDocument(document.id, f.id);
                      Navigator.pop(ctx);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
