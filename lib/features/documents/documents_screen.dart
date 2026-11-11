import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/providers/documents_provider.dart';
import '../../core/routing/app_router.dart';
import '../../core/widgets/search_field.dart';
import '../../core/widgets/app_filter_chip.dart';
import '../../core/widgets/segmented_control.dart';
import '../../core/widgets/document_card.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../share/share_export_sheet.dart';

/// Screen 2: Documents Screen with search, filters, grid/list view, sorting, and selection mode.
class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showSortMenu(BuildContext context, DocumentsProvider provider) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: AppDimensions.borderSheet),
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text(
                    'Sort by',
                    style: AppTypography.subsectionTitle.copyWith(
                      color: isDark ? AppColors.darkText : AppColors.textPrimary,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.access_time_rounded),
                  title: const Text('Recent'),
                  trailing: provider.sort == DocumentSort.recent ? const Icon(Icons.check_rounded, color: AppColors.primary) : null,
                  onTap: () {
                    provider.setSort(DocumentSort.recent);
                    Navigator.pop(ctx);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.sort_by_alpha_rounded),
                  title: const Text('Name (A-Z)'),
                  trailing: provider.sort == DocumentSort.name ? const Icon(Icons.check_rounded, color: AppColors.primary) : null,
                  onTap: () {
                    provider.setSort(DocumentSort.name);
                    Navigator.pop(ctx);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.history_rounded),
                  title: const Text('Oldest'),
                  trailing: provider.sort == DocumentSort.oldest ? const Icon(Icons.check_rounded, color: AppColors.primary) : null,
                  onTap: () {
                    provider.setSort(DocumentSort.oldest);
                    Navigator.pop(ctx);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showMoveDialog(BuildContext context, DocumentsProvider provider) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: AppDimensions.borderSheet),
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text(
                    'Move to folder',
                    style: AppTypography.subsectionTitle.copyWith(
                      color: isDark ? AppColors.darkText : AppColors.textPrimary,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.folder_off_outlined),
                  title: const Text('No folder (Root)'),
                  onTap: () {
                    for (final id in provider.selectedIds) {
                      provider.moveDocument(id, null);
                    }
                    provider.setSelectionMode(false);
                    Navigator.pop(ctx);
                  },
                ),
                ...provider.folders.map(
                  (f) => ListTile(
                    leading: Icon(f.icon, color: f.color),
                    title: Text(f.name),
                    onTap: () {
                      for (final id in provider.selectedIds) {
                        provider.moveDocument(id, f.id);
                      }
                      provider.setSelectionMode(false);
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final docsProvider = context.watch<DocumentsProvider>();
    final docs = docsProvider.filteredDocuments;
    final isSelection = docsProvider.isSelectionMode;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      appBar: AppBar(
        title: isSelection
            ? Text('${docsProvider.selectedCount} selected')
            : const Text('Documents'),
        leading: isSelection
            ? IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => docsProvider.setSelectionMode(false),
              )
            : null,
        actions: [
          if (isSelection) ...[
            TextButton(
              onPressed: docsProvider.selectAll,
              child: const Text('Select All'),
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.checklist_rounded),
              tooltip: 'Select mode',
              onPressed: () => docsProvider.setSelectionMode(true),
            ),
            IconButton(
              icon: const Icon(Icons.filter_list_rounded),
              tooltip: 'Sort',
              onPressed: () => _showSortMenu(context, docsProvider),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: SearchField(
              controller: _searchController,
              hintText: 'Search documents...',
              onChanged: (q) => docsProvider.setSearchQuery(q),
              onClear: () => docsProvider.setSearchQuery(''),
            ),
          ),

          // Filters and View Toggle Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: [
                        AppFilterChip(
                          label: 'All',
                          isSelected: docsProvider.filter == DocumentFilter.all,
                          onTap: () => docsProvider.setFilter(DocumentFilter.all),
                        ),
                        const SizedBox(width: 8),
                        AppFilterChip(
                          label: 'PDFs',
                          isSelected: docsProvider.filter == DocumentFilter.pdfs,
                          onTap: () => docsProvider.setFilter(DocumentFilter.pdfs),
                        ),
                        const SizedBox(width: 8),
                        AppFilterChip(
                          label: 'Images',
                          isSelected: docsProvider.filter == DocumentFilter.images,
                          onTap: () => docsProvider.setFilter(DocumentFilter.images),
                        ),
                        const SizedBox(width: 8),
                        AppFilterChip(
                          label: 'Favorites',
                          icon: Icons.star_rounded,
                          isSelected: docsProvider.filter == DocumentFilter.favorites,
                          onTap: () => docsProvider.setFilter(DocumentFilter.favorites),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Grid/List toggle
                SegmentedControl<DocumentViewMode>(
                  items: const {
                    DocumentViewMode.grid: 'Grid',
                    DocumentViewMode.list: 'List',
                  },
                  selectedValue: docsProvider.viewMode,
                  onValueChanged: (mode) => docsProvider.setViewMode(mode),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Document List / Grid
          Expanded(
            child: docsProvider.documents.isEmpty
                ? EmptyState(
                    icon: Icons.folder_open_rounded,
                    title: 'No documents yet',
                    description: 'Scan or import your first document to get started.',
                    buttonLabel: 'Scan document',
                    onButtonPressed: () => context.push(AppRouter.scanner),
                  )
                : docs.isEmpty
                    ? EmptyState(
                        icon: Icons.search_off_rounded,
                        title: 'No matching documents',
                        description: 'Try adjusting your search terms or filter selection.',
                      )
                    : docsProvider.viewMode == DocumentViewMode.grid
                        ? _buildGridView(docs, docsProvider)
                        : _buildListView(docs, docsProvider),
          ),

          // Selection Action Bar (Share, Move, Delete)
          if (isSelection) _buildSelectionBottomBar(context, docsProvider, isDark),
        ],
      ),
    );
  }

  Widget _buildGridView(List<dynamic> docs, DocumentsProvider docsProvider) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 0.72,
      ),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        final doc = docs[index];
        final isSelected = docsProvider.selectedIds.contains(doc.id);

        return DocumentCard(
          document: doc,
          isGrid: true,
          isSelectionMode: docsProvider.isSelectionMode,
          isSelected: isSelected,
          onTap: () {
            if (docsProvider.isSelectionMode) {
              docsProvider.toggleSelect(doc.id);
            } else {
              context.push('/viewer/${doc.id}');
            }
          },
          onLongPress: () {
            if (!docsProvider.isSelectionMode) {
              docsProvider.setSelectionMode(true);
              docsProvider.toggleSelect(doc.id);
            }
          },
        );
      },
    );
  }

  Widget _buildListView(List<dynamic> docs, DocumentsProvider docsProvider) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      physics: const BouncingScrollPhysics(),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        final doc = docs[index];
        final isSelected = docsProvider.selectedIds.contains(doc.id);

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DocumentCard(
            document: doc,
            isGrid: false,
            isSelectionMode: docsProvider.isSelectionMode,
            isSelected: isSelected,
            onTap: () {
              if (docsProvider.isSelectionMode) {
                docsProvider.toggleSelect(doc.id);
              } else {
                context.push('/viewer/${doc.id}');
              }
            },
            onLongPress: () {
              if (!docsProvider.isSelectionMode) {
                docsProvider.setSelectionMode(true);
                docsProvider.toggleSelect(doc.id);
              }
            },
          ),
        );
      },
    );
  }

  Widget _buildSelectionBottomBar(BuildContext context, DocumentsProvider provider, bool isDark) {
    final hasSelection = provider.selectedCount > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.border,
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            // Share
            _buildSelectionAction(
              icon: Icons.share_rounded,
              label: 'Share',
              isEnabled: hasSelection,
              onTap: () {
                ShareExportSheet.show(context, documentTitle: '${provider.selectedCount} documents');
              },
            ),
            // Move
            _buildSelectionAction(
              icon: Icons.drive_file_move_outlined,
              label: 'Move',
              isEnabled: hasSelection,
              onTap: () => _showMoveDialog(context, provider),
            ),
            // Delete
            _buildSelectionAction(
              icon: Icons.delete_outline_rounded,
              label: 'Delete',
              isDestructive: true,
              isEnabled: hasSelection,
              onTap: () async {
                final confirm = await ConfirmDialog.show(
                  context,
                  title: 'Delete ${provider.selectedCount} ${provider.selectedCount == 1 ? 'document' : 'documents'}?',
                  message: 'This will remove the selected documents and all their pages.',
                  confirmLabel: 'Delete',
                  isDestructive: true,
                );
                if (confirm == true) {
                  provider.deleteSelected();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isEnabled = true,
    bool isDestructive = false,
  }) {
    final color = !isEnabled
        ? AppColors.textSecondary.withAlpha(80)
        : (isDestructive ? AppColors.error : AppColors.primary);

    return InkWell(
      onTap: isEnabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: AppTypography.badge.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}
