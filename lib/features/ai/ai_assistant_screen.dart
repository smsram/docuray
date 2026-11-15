import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/providers/ai_provider.dart';
import '../../core/providers/documents_provider.dart';
import '../../models/models.dart';

/// Screen 9: Contextual Document AI Assistant powered by Qwen3-VL-8B (ZeroGPU).
/// Features real-time SSE streaming, clean inline Markdown rendering,
/// compact top-bar circular allowance meter, attached gallery images,
/// and contextual mode routing.
class AiAssistantScreen extends StatefulWidget {
  final String documentId;
  final int initialPageIndex;

  const AiAssistantScreen({
    super.key,
    required this.documentId,
    this.initialPageIndex = 0,
  });

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final List<File> _attachedImages = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final doc = context.read<DocumentsProvider>().getDocument(widget.documentId);
      if (doc != null) {
        context.read<AiProvider>().setDocumentContext(
              documentId: doc.id,
              title: doc.title,
              pageCount: doc.pageCount,
              document: doc,
              initialPageIndex: widget.initialPageIndex,
            );
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        final max = _scrollController.position.maxScrollExtent;
        final current = _scrollController.position.pixels;
        // Only auto-scroll if user is already within 150px of bottom or if user sent message
        if (force || (max - current <= 150)) {
          _scrollController.animateTo(
            max,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      }
    });
  }

  Future<void> _pickGalleryImages() async {
    try {
      final picker = ImagePicker();
      final pickedList = await picker.pickMultiImage(imageQuality: 85);
      if (pickedList.isNotEmpty) {
        setState(() {
          for (final item in pickedList) {
            _attachedImages.add(File(item.path));
          }
        });
      }
    } catch (e) {
      debugPrint('[DocuRay AI] Error picking gallery image: $e');
    }
  }

  void _removeAttachedImage(int index) {
    if (index >= 0 && index < _attachedImages.length) {
      setState(() {
        _attachedImages.removeAt(index);
      });
    }
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty && _attachedImages.isEmpty) return;

    final imagesToSend = List<File>.from(_attachedImages);
    _textController.clear();
    _focusNode.unfocus();
    setState(() {
      _attachedImages.clear();
    });

    final doc = context.read<DocumentsProvider>().getDocument(widget.documentId);
    context.read<AiProvider>().sendMessage(
          text,
          document: doc,
          attachedImages: imagesToSend.isNotEmpty ? imagesToSend : null,
        );
    _scrollToBottom(force: true);
  }

  void _triggerQuickAction(String actionType) {
    final doc = context.read<DocumentsProvider>().getDocument(widget.documentId);
    context.read<AiProvider>().triggerQuickAction(actionType, document: doc);
    _scrollToBottom(force: true);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final aiProvider = context.watch<AiProvider>();
    final doc = context.watch<DocumentsProvider>().getDocument(widget.documentId);
    final messages = aiProvider.messages;
    final hasUserMessage = messages.any((m) => m.role == MessageRole.user);

    // Auto-scroll on new streaming chunks if near bottom
    if (aiProvider.isGenerating) {
      _scrollToBottom();
    }

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 16,
                  color: isDark ? AppColors.darkPrimary : AppColors.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  'DocuRay AI',
                  style: AppTypography.screenTitle.copyWith(
                    fontSize: 17,
                    color: isDark ? AppColors.darkText : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: (isDark ? AppColors.darkPrimary : AppColors.primary).withAlpha(30),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Qwen3-VL',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: isDark ? AppColors.darkPrimary : AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              aiProvider.documentTitle.isNotEmpty ? aiProvider.documentTitle : (doc?.title ?? 'Document'),
              style: AppTypography.caption.copyWith(
                color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          _buildCircularUsageRing(aiProvider, isDark),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Clear conversation',
            onPressed: () => aiProvider.clearConversation(),
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Conversation Message Stream
          Expanded(
            child: messages.isEmpty
                ? _buildEmptyState(isDark)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final isLastMessage = index == messages.length - 1;
                      return _buildMessageBubble(
                        msg: msg,
                        isDark: isDark,
                        isLast: isLastMessage,
                        aiProvider: aiProvider,
                        doc: doc,
                      );
                    },
                  ),
          ),

          // 2. Quick Action Chips (Shown only when conversation is empty)
          if (!hasUserMessage)
            _buildQuickActionsBar(isDark),

          // 3. Compact Context Mode Selector Bar ([Auto] [No Document] [Page X] [Entire Doc])
          _buildContextModeSelector(aiProvider, doc, isDark),

          // 4. Attached Images Preview Strip
          if (_attachedImages.isNotEmpty)
            _buildAttachedImagesPreview(isDark),

          // 5. Chat Input Field with Gallery Attachment + Send/Stop
          _buildChatInputField(aiProvider, isDark),
        ],
      ),
    );
  }

  /// Compact circular usage indicator in the AppBar.
  Widget _buildCircularUsageRing(AiProvider aiProvider, bool isDark) {
    final remaining = aiProvider.remainingSecondsToday;
    final isExhausted = aiProvider.isAllowanceExhausted;
    final progress = (120 - aiProvider.usedSecondsToday).clamp(0, 120) / 120.0;

    Color ringColor;
    if (isExhausted) {
      ringColor = AppColors.error;
    } else if (remaining <= 30) {
      ringColor = AppColors.warning;
    } else {
      ringColor = AppColors.success;
    }

    return Tooltip(
      message: isExhausted
          ? 'Daily free quota reached (2 min / day). Resets at ${aiProvider.resetTimeFormatted}.'
          : 'Free Allowance: ${remaining}s / 120s remaining',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Center(
          child: SizedBox(
            width: 30,
            height: 30,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 2.8,
                  backgroundColor: isDark ? AppColors.darkBorder : Colors.black12,
                  valueColor: AlwaysStoppedAnimation<Color>(ringColor),
                ),
                Text(
                  '${remaining}s',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: ringColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Compact context selector bar positioned adjacent to the input field.
  Widget _buildContextModeSelector(AiProvider aiProvider, Document? doc, bool isDark) {
    final currentMode = aiProvider.contextMode;
    final totalPages = doc?.pageCount ?? 1;
    final currentPageNum = aiProvider.currentPageIndex + 1;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2228) : const Color(0xFFF8FAFC),
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.border,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildModePill(
              label: 'Auto',
              icon: Icons.auto_mode_rounded,
              isSelected: currentMode == AiContextMode.auto,
              onTap: () => aiProvider.setContextMode(AiContextMode.auto),
              isDark: isDark,
            ),
            const SizedBox(width: 6),
            _buildModePill(
              label: 'No Document',
              icon: Icons.chat_bubble_outline_rounded,
              isSelected: currentMode == AiContextMode.noDocument,
              onTap: () => aiProvider.setContextMode(AiContextMode.noDocument),
              isDark: isDark,
            ),
            const SizedBox(width: 6),
            _buildModePill(
              label: 'Page $currentPageNum',
              icon: Icons.image_outlined,
              isSelected: currentMode == AiContextMode.currentPage,
              onTap: () {
                if (totalPages > 1) {
                  _showPagePicker(aiProvider, totalPages);
                } else {
                  aiProvider.setContextMode(AiContextMode.currentPage);
                }
              },
              isDark: isDark,
              trailing: totalPages > 1
                  ? Icon(
                      Icons.arrow_drop_down,
                      size: 16,
                      color: currentMode == AiContextMode.currentPage
                          ? (isDark ? Colors.black : Colors.white)
                          : (isDark ? AppColors.darkTextSecondary : AppColors.textSecondary),
                    )
                  : null,
            ),
            const SizedBox(width: 6),
            _buildModePill(
              label: 'Entire Doc ($totalPages p)',
              icon: Icons.library_books_outlined,
              isSelected: currentMode == AiContextMode.entireDoc,
              onTap: () => aiProvider.setContextMode(AiContextMode.entireDoc),
              isDark: isDark,
            ),
          ],
        ),
      ),
    );
  }

  void _showPagePicker(AiProvider aiProvider, int totalPages) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'Select Page to Focus',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
            ...List.generate(totalPages, (i) {
              final isCurrent = aiProvider.currentPageIndex == i;
              return ListTile(
                leading: Icon(
                  Icons.description_outlined,
                  color: isCurrent ? AppColors.primary : null,
                ),
                title: Text('Page ${i + 1}'),
                trailing: isCurrent ? const Icon(Icons.check, color: AppColors.primary) : null,
                onTap: () {
                  aiProvider.setCurrentPageIndex(i);
                  aiProvider.setContextMode(AiContextMode.currentPage);
                  Navigator.pop(ctx);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildModePill({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
    Widget? trailing,
  }) {
    final activeColor = isDark ? AppColors.darkPrimary : AppColors.primary;
    final activeText = isDark ? const Color(0xFF0F172A) : Colors.white;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor
              : (isDark ? const Color(0xFF262C34) : Colors.white),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? activeColor
                : (isDark ? AppColors.darkBorder : AppColors.border),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected
                  ? activeText
                  : (isDark ? AppColors.darkTextSecondary : AppColors.textSecondary),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? activeText
                    : (isDark ? AppColors.darkText : AppColors.textPrimary),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble({
    required AIMessage msg,
    required bool isDark,
    required bool isLast,
    required AiProvider aiProvider,
    required Document? doc,
  }) {
    final isUser = msg.role == MessageRole.user;
    final isAssistantGenerating = isLast && !isUser && aiProvider.isGenerating;

    if (isUser) {
      // User message: styled bubble on the right
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Align(
          alignment: Alignment.centerRight,
          child: Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkPrimary : AppColors.primary,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (msg.attachedImagePaths != null && msg.attachedImagePaths!.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: msg.attachedImagePaths!.map((path) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(path),
                            width: 68,
                            height: 68,
                            fit: BoxFit.cover,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
                SelectableText(
                  msg.content,
                  style: AppTypography.body.copyWith(
                    color: isDark ? const Color(0xFF0F172A) : Colors.white,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Assistant message: clean markdown rendered directly without avatar circle or card bubble
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (msg.isLoading && msg.content.isEmpty) ...[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isDark ? AppColors.darkPrimary : AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Thinking...',
                      style: AppTypography.caption.copyWith(
                        color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ] else ...[
                MarkdownBody(
                  data: msg.content + (isAssistantGenerating ? ' ▍' : ''),
                  selectable: true,
                  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                    p: AppTypography.body.copyWith(
                      color: isDark ? AppColors.darkText : AppColors.textPrimary,
                      height: 1.5,
                    ),
                    code: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12.5,
                      backgroundColor: isDark ? const Color(0xFF1E2228) : const Color(0xFFF1F5F9),
                      color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A),
                    ),
                    codeblockDecoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E2228) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isDark ? AppColors.darkBorder : AppColors.border,
                      ),
                    ),
                  ),
                ),
              ],

              // Response Actions (Copy & Retry)
              if (msg.content.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 14),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        tooltip: 'Copy response',
                        color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: msg.content));
                          HapticFeedback.lightImpact();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Response copied to clipboard.'),
                              duration: Duration(seconds: 1),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                      ),
                      if (msg.hasError || isLast) ...[
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded, size: 14),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          tooltip: 'Retry',
                          color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                          onPressed: () => aiProvider.retryLastMessage(document: doc),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: (isDark ? AppColors.darkPrimary : AppColors.primary).withAlpha(20),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.auto_awesome_rounded,
              size: 24,
              color: isDark ? AppColors.darkPrimary : AppColors.primary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'What would you like to know?',
            style: AppTypography.sectionTitle.copyWith(
              color: isDark ? AppColors.darkText : AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Ask questions about text, tables, data, or summaries in this document.',
            textAlign: TextAlign.center,
            style: AppTypography.secondary.copyWith(
              color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// Compact suggestion chips shown only when conversation is empty.
  Widget _buildQuickActionsBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            _buildQuickActionChip('Summarize', Icons.summarize_outlined, () => _triggerQuickAction('summarize'), isDark),
            const SizedBox(width: 8),
            _buildQuickActionChip('Explain simply', Icons.lightbulb_outline_rounded, () => _triggerQuickAction('explain'), isDark),
            const SizedBox(width: 8),
            _buildQuickActionChip('Extract info', Icons.data_object_rounded, () => _triggerQuickAction('extract'), isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionChip(String label, IconData icon, VoidCallback onTap, bool isDark) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF262C34) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isDark ? AppColors.darkPrimary : AppColors.primary),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTypography.buttonSmall.copyWith(
                fontSize: 12,
                color: isDark ? AppColors.darkText : AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Thumbnail preview row for attached gallery images.
  Widget _buildAttachedImagesPreview(bool isDark) {
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _attachedImages.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  _attachedImages[index],
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                top: 2,
                right: 2,
                child: InkWell(
                  onTap: () => _removeAttachedImage(index),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Colors.black87,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, size: 12, color: Colors.white),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildChatInputField(AiProvider aiProvider, bool isDark) {
    final isExhausted = aiProvider.isAllowanceExhausted;
    final isGenerating = aiProvider.isGenerating;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 16, 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 22),
              tooltip: 'Attach image from gallery',
              color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
              onPressed: isExhausted ? null : _pickGalleryImages,
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF262C34) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(AppDimensions.radiusInput),
                  border: Border.all(
                    color: isDark ? AppColors.darkBorder : AppColors.border,
                  ),
                ),
                child: TextField(
                  controller: _textController,
                  focusNode: _focusNode,
                  enabled: !isExhausted,
                  style: AppTypography.body.copyWith(
                    color: isDark ? AppColors.darkText : AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: isExhausted
                        ? 'Daily free quota reached'
                        : 'Ask about this document...',
                    hintStyle: AppTypography.body.copyWith(
                      color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                      fontSize: 14,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                  onSubmitted: (_) {
                    if (!isGenerating && !isExhausted) {
                      _sendMessage();
                    }
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Send or Stop Generation CTA
            if (isGenerating) ...[
              IconButton.filled(
                onPressed: () => aiProvider.stopGeneration(),
                icon: const Icon(Icons.stop_rounded, size: 20),
                tooltip: 'Stop generating',
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                ),
              ),
            ] else ...[
              IconButton.filled(
                onPressed: isExhausted ? null : _sendMessage,
                icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                tooltip: isExhausted ? 'Daily quota reached' : 'Send',
                style: IconButton.styleFrom(
                  backgroundColor: isExhausted
                      ? Colors.grey
                      : (isDark ? AppColors.darkPrimary : AppColors.primary),
                  foregroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
