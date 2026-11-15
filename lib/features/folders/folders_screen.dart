import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/providers/documents_provider.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/document_card.dart';
import '../../models/models.dart';

/// Screen 15: Folders Management Screen with Create, Rename, and Delete folder support.
class FoldersScreen extends StatelessWidget {
  const FoldersScreen({super.key});

  void _showCreateFolderDialog(BuildContext context, DocumentsProvider provider) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Folder name (e.g. Tax Returns)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                provider.createFolder(name);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showFolderOptions(BuildContext context, Folder folder, DocumentsProvider provider) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: AppDimensions.borderSheet),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename folder'),
              onTap: () {
                Navigator.pop(ctx);
                _showRenameFolderDialog(context, folder, provider);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
              title: const Text('Delete folder', style: TextStyle(color: AppColors.error)),
              onTap: () async {
                Navigator.pop(ctx);
                final confirm = await ConfirmDialog.show(
                  context,
                  title: 'Delete "${folder.name}" folder?',
                  message: 'Documents inside this folder will be kept and moved to the root document list.',
                  confirmLabel: 'Delete',
                  isDestructive: true,
                );
                if (confirm == true) {
                  provider.deleteFolder(folder.id);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showRenameFolderDialog(BuildContext context, Folder folder, DocumentsProvider provider) {
    final controller = TextEditingController(text: folder.name);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Folder name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isNotEmpty && newName != folder.name) {
                provider.renameFolder(folder.id, newName);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Folder renamed.')),
                );
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final docsProvider = context.watch<DocumentsProvider>();
    final folders = docsProvider.folders;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('Folders'),
        actions: [
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: 'New folder',
            onPressed: () => _showCreateFolderDialog(context, docsProvider),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView.separated(
          padding: AppDimensions.screenPadding,
          itemCount: folders.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final f = folders[index];
            final count = docsProvider.documents.where((d) => d.folderId == f.id).length;

            return AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              onTap: () => _openFolderContents(context, f),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: f.color.withAlpha(20),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(f.icon, color: f.color, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          f.name,
                          style: AppTypography.bodyMedium.copyWith(
                            color: isDark ? AppColors.darkText : AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$count ${count == 1 ? 'document' : 'documents'}',
                          style: AppTypography.secondary.copyWith(
                            color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_horiz_rounded),
                    onPressed: () => _showFolderOptions(context, f, docsProvider),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _openFolderContents(BuildContext context, Folder folder) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => _FolderContentsScreen(folder: folder),
      ),
    );
  }
}

class _FolderContentsScreen extends StatelessWidget {
  final Folder folder;

  const _FolderContentsScreen({required this.folder});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final docsProvider = context.watch<DocumentsProvider>();
    final docsInFolder = docsProvider.documents.where((d) => d.folderId == folder.id).toList();

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Icon(folder.icon, color: folder.color, size: 20),
            const SizedBox(width: 8),
            Text(folder.name),
          ],
        ),
      ),
      body: SafeArea(
        child: docsInFolder.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.folder_open_rounded,
                      size: 48,
                      color: isDark ? AppColors.darkTextSecondary.withAlpha(120) : AppColors.textSecondary.withAlpha(120),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'This folder is empty',
                      style: AppTypography.subsectionTitle.copyWith(
                        color: isDark ? AppColors.darkText : AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Move documents here using the options menu on any document.',
                      style: AppTypography.secondary,
                    ),
                  ],
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 80),
                itemCount: docsInFolder.length,
                separatorBuilder: (context, index) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final doc = docsInFolder[index];
                  return DocumentCard(
                    document: doc,
                    isGrid: false,
                    onTap: () => context.push('/viewer/${doc.id}'),
                  );
                },
              ),
      ),
    );
  }
}
