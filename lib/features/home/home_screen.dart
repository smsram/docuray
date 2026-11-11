import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/providers/documents_provider.dart';
import '../../core/routing/app_router.dart';
import '../../core/widgets/search_field.dart';
import '../../core/widgets/app_filter_chip.dart';
import '../../core/widgets/document_card.dart';
import '../../core/widgets/empty_state.dart';
import '../../models/models.dart';

/// Unified Home Screen / Document Library (Home + Files merged).
/// Displays greeting, search, category filters, and real locally persisted documents
/// with long-press multi-selection and batch operations.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll(List<Document> docs) {
    setState(() {
      if (_selectedIds.length == docs.length) {
        _selectedIds.clear();
        _isSelectionMode = false;
      } else {
        _selectedIds.addAll(docs.map((d) => d.id));
      }
    });
  }

  void _cancelSelection() {
    setState(() {
      _selectedIds.clear();
      _isSelectionMode = false;
    });
  }

  Future<void> _deleteSelected(DocumentsProvider provider) async {
    if (_selectedIds.isEmpty) return;

    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $count ${count == 1 ? "Document" : "Documents"}?'),
        content: const Text('This action will permanently delete the selected documents and PDFs.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final idsToDelete = List<String>.from(_selectedIds);
      for (final id in idsToDelete) {
        await provider.deleteDocument(id);
      }
      _cancelSelection();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted $count ${count == 1 ? "document" : "documents"}')),
        );
      }
    }
  }

  Future<void> _shareSelected(DocumentsProvider provider) async {
    if (_selectedIds.isEmpty) return;

    final filesToShare = <XFile>[];
    for (final doc in provider.documents) {
      if (_selectedIds.contains(doc.id) && doc.pdfPath != null) {
        final f = File(doc.pdfPath!);
        if (await f.exists()) {
          filesToShare.add(XFile(doc.pdfPath!, name: '${doc.title}.pdf'));
        }
      }
    }

    if (filesToShare.isNotEmpty) {
      await SharePlus.instance.share(
        ShareParams(
          files: filesToShare,
          text: 'Sharing ${filesToShare.length} documents from DocuRay',
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No PDF files found to share.')),
      );
    }
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
                  trailing: provider.sort == DocumentSort.recent
                      ? const Icon(Icons.check_rounded, color: AppColors.primary)
                      : null,
                  onTap: () {
                    provider.setSort(DocumentSort.recent);
                    Navigator.pop(ctx);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.sort_by_alpha_rounded),
                  title: const Text('Name (A-Z)'),
                  trailing: provider.sort == DocumentSort.name
                      ? const Icon(Icons.check_rounded, color: AppColors.primary)
                      : null,
                  onTap: () {
                    provider.setSort(DocumentSort.name);
                    Navigator.pop(ctx);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.history_rounded),
                  title: const Text('Oldest'),
                  trailing: provider.sort == DocumentSort.oldest
                      ? const Icon(Icons.check_rounded, color: AppColors.primary)
                      : null,
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final docsProvider = context.watch<DocumentsProvider>();
    final docs = docsProvider.filteredDocuments;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // 1. Top Header (Greeting OR Selection Mode Action Bar)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: _isSelectionMode
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.close_rounded),
                                onPressed: _cancelSelection,
                                tooltip: 'Cancel',
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${_selectedIds.length} selected',
                                style: AppTypography.screenTitle.copyWith(
                                  color: isDark ? AppColors.darkText : AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              IconButton(
                                icon: Icon(
                                  _selectedIds.length == docs.length
                                      ? Icons.deselect_rounded
                                      : Icons.select_all_rounded,
                                ),
                                tooltip: _selectedIds.length == docs.length ? 'Deselect All' : 'Select All',
                                onPressed: () => _selectAll(docs),
                              ),
                              IconButton(
                                icon: const Icon(Icons.share_rounded),
                                tooltip: 'Share Selected',
                                onPressed: () => _shareSelected(docsProvider),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
                                tooltip: 'Delete Selected',
                                onPressed: () => _deleteSelected(docsProvider),
                              ),
                            ],
                          ),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _getGreeting(),
                                style: AppTypography.largeTitle.copyWith(
                                  color: isDark ? AppColors.darkText : AppColors.textPrimary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${docsProvider.documents.length} ${docsProvider.documents.length == 1 ? 'document' : 'documents'} stored locally',
                                style: AppTypography.secondaryMedium.copyWith(
                                  color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: Icon(
                              docsProvider.viewMode == DocumentViewMode.grid
                                  ? Icons.view_list_rounded
                                  : Icons.grid_view_rounded,
                              color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                            ),
                            tooltip: docsProvider.viewMode == DocumentViewMode.grid ? 'List View' : 'Grid View',
                            onPressed: () {
                              docsProvider.setViewMode(
                                docsProvider.viewMode == DocumentViewMode.grid
                                    ? DocumentViewMode.list
                                    : DocumentViewMode.grid,
                              );
                            },
                          ),
                        ],
                      ),
              ),
            ),

            // 2. Search Field (hidden during selection mode)
            if (!_isSelectionMode)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  child: SearchField(
                    controller: _searchController,
                    hintText: 'Search documents...',
                    onChanged: docsProvider.setSearchQuery,
                    onClear: () => docsProvider.setSearchQuery(''),
                  ),
                ),
              ),

            // 3. Filter Chips & Sort Row (hidden during selection mode)
            if (!_isSelectionMode)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              AppFilterChip(
                                label: 'All',
                                isSelected: docsProvider.filter == DocumentFilter.all,
                                onTap: () => docsProvider.setFilter(DocumentFilter.all),
                              ),
                              const SizedBox(width: 8),
                              AppFilterChip(
                                label: 'Favorites',
                                icon: Icons.star_rounded,
                                isSelected: docsProvider.filter == DocumentFilter.favorites,
                                onTap: () => docsProvider.setFilter(DocumentFilter.favorites),
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
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.sort_rounded, size: 20),
                        color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                        tooltip: 'Sort',
                        onPressed: () => _showSortMenu(context, docsProvider),
                      ),
                    ],
                  ),
                ),
              ),

            // 4. Documents List or Empty State
            if (docsProvider.isLoading)
              const SliverFillRemaining(
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              )
            else if (docs.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.document_scanner_outlined,
                  title: 'No documents yet',
                  description: 'Scan your first document to get started.',
                  buttonLabel: 'Scan document',
                  onButtonPressed: () => context.push(AppRouter.scanner),
                ),
              )
            else if (docsProvider.viewMode == DocumentViewMode.grid)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 80),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.72,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final doc = docs[index];
                      final isSelected = _selectedIds.contains(doc.id);

                      return DocumentCard(
                        document: doc,
                        isGrid: true,
                        isSelectionMode: _isSelectionMode,
                        isSelected: isSelected,
                        onLongPress: () {
                          if (!_isSelectionMode) {
                            setState(() {
                              _isSelectionMode = true;
                              _selectedIds.add(doc.id);
                            });
                          }
                        },
                        onTap: () {
                          if (_isSelectionMode) {
                            _toggleSelection(doc.id);
                          } else {
                            context.push('/viewer/${doc.id}');
                          }
                        },
                      );
                    },
                    childCount: docs.length,
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 80),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final doc = docs[index];
                      final isSelected = _selectedIds.contains(doc.id);

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: DocumentCard(
                          document: doc,
                          isGrid: false,
                          isSelectionMode: _isSelectionMode,
                          isSelected: isSelected,
                          onLongPress: () {
                            if (!_isSelectionMode) {
                              setState(() {
                                _isSelectionMode = true;
                                _selectedIds.add(doc.id);
                              });
                            }
                          },
                          onTap: () {
                            if (_isSelectionMode) {
                              _toggleSelection(doc.id);
                            } else {
                              context.push('/viewer/${doc.id}');
                            }
                          },
                        ),
                      );
                    },
                    childCount: docs.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
