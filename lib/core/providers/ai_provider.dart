import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/models.dart';
import '../services/hf_vision_service.dart';
import '../services/document_retrieval_service.dart';

/// Context modes supported by the DocuRay AI Assistant.
enum AiContextMode {
  auto,
  noDocument,
  currentPage,
  entireDoc,
}

/// Provider managing DocuRay AI Assistant state, context routing,
/// streaming Qwen3-VL-8B responses, cancellation, and daily allowance tracking.
class AiProvider extends ChangeNotifier {
  final HfVisionService _hfService = HfVisionService.instance;
  final DocumentRetrievalService _retrievalService = DocumentRetrievalService.instance;

  String _documentId = '';
  String _documentTitle = '';
  int _documentPageCount = 1;
  Document? _currentDocument;

  int _currentPageIndex = 0;
  AiContextMode _contextMode = AiContextMode.auto;

  final Map<String, List<AIMessage>> _conversations = {};
  bool _isGenerating = false;
  String? _errorMessage;
  int? _liveRemainingOverride;

  String get documentId => _documentId;
  String get documentTitle => _documentTitle;
  int get documentPageCount => _documentPageCount;
  Document? get currentDocument => _currentDocument;
  int get currentPageIndex => _currentPageIndex;
  AiContextMode get contextMode => _contextMode;

  bool get isGenerating => _isGenerating;
  bool get isThinking => _isGenerating; // Backward compatibility
  String? get errorMessage => _errorMessage;

  List<AIMessage> get messages => _conversations[_documentId] ?? [];

  // Daily usage stats
  int get usedSecondsToday => _hfService.usedSecondsToday;
  int get remainingSecondsToday => _liveRemainingOverride ?? _hfService.remainingSecondsToday;
  double get usageProgress => _hfService.usageProgress;
  bool get isAllowanceExhausted => _hfService.isAllowanceExhausted;
  String get resetTimeFormatted => _hfService.resetTimeFormatted;

  AiProvider() {
    _initStats();
  }

  Future<void> _initStats() async {
    await _hfService.initUsageTracking(forceRefresh: true);
    notifyListeners();
  }

  void setContextMode(AiContextMode mode) {
    _contextMode = mode;
    notifyListeners();
  }

  void setCurrentPageIndex(int index) {
    if (_currentPageIndex != index) {
      _currentPageIndex = index;
      notifyListeners();
    }
  }

  void setDocumentContext({
    required String documentId,
    required String title,
    required int pageCount,
    Document? document,
    int initialPageIndex = 0,
  }) {
    _documentId = documentId;
    _documentTitle = title;
    _documentPageCount = pageCount;
    _currentDocument = document;
    _currentPageIndex = initialPageIndex.clamp(0, pageCount > 0 ? pageCount - 1 : 0);
    _errorMessage = null;

    if (!_conversations.containsKey(documentId) || _conversations[documentId]!.isEmpty) {
      _conversations[documentId] = [
        AIMessage(
          id: 'welcome_msg_${DateTime.now().millisecondsSinceEpoch}',
          role: MessageRole.assistant,
          content: 'Hello! I am DocuRay AI, powered by Qwen3-VL-8B. '
              'I can read, inspect, and analyze "$title" ($pageCount ${pageCount == 1 ? 'page' : 'pages'}).\n\n'
              'Ask any question below, or tap one of the quick actions.',
          timestamp: DateTime.now(),
        ),
      ];
    }
    notifyListeners();
  }

  /// Sends a user message to Qwen3-VL-8B with intelligent context routing.
  Future<void> sendMessage(String text, {Document? document, List<File>? attachedImages}) async {
    final trimmedText = text.trim();
    if (trimmedText.isEmpty && (attachedImages == null || attachedImages.isEmpty)) return;
    if (_isGenerating) return;

    await _hfService.initUsageTracking(forceRefresh: true);
    if (_hfService.isAllowanceExhausted) {
      _errorMessage = 'Daily free allowance reached (2 min / day). Resets at ${_hfService.resetTimeFormatted}.';
      notifyListeners();
      return;
    }

    final doc = document ?? _currentDocument;

    // 1. Add user message with attached image paths if present
    final userMessage = AIMessage(
      id: 'usr_${DateTime.now().millisecondsSinceEpoch}',
      role: MessageRole.user,
      content: trimmedText.isNotEmpty ? trimmedText : 'Analyze attached image',
      timestamp: DateTime.now(),
      attachedImagePaths: attachedImages?.map((f) => f.path).toList(),
    );

    _conversations.putIfAbsent(_documentId, () => []);
    _conversations[_documentId]!.add(userMessage);

    // 2. Add assistant placeholder message
    final assistantMsgId = 'ast_${DateTime.now().millisecondsSinceEpoch}';
    final placeholderAssistant = AIMessage(
      id: assistantMsgId,
      role: MessageRole.assistant,
      content: '',
      timestamp: DateTime.now(),
      isLoading: true,
    );
    _conversations[_documentId]!.add(placeholderAssistant);

    _isGenerating = true;
    _errorMessage = null;
    notifyListeners();

    // 3. Resolve context mode
    String effectiveMode;
    switch (_contextMode) {
      case AiContextMode.auto:
        effectiveMode = doc != null
            ? _retrievalService.determineAutoMode(
                query: trimmedText,
                document: doc,
                currentPageIndex: _currentPageIndex,
              )
            : 'noDocument';
        break;
      case AiContextMode.noDocument:
        effectiveMode = 'noDocument';
        break;
      case AiContextMode.currentPage:
        effectiveMode = 'currentPage';
        break;
      case AiContextMode.entireDoc:
        effectiveMode = 'entireDoc';
        break;
    }

    String promptToSend = trimmedText.isNotEmpty ? trimmedText : 'Please describe or analyze this attached image.';
    File? imageToSend;
    String systemPrompt = 'You are DocuRay AI — an intelligent, concise, and document-aware assistant. '
        'Format responses cleanly using Markdown (headers, lists, bold text, code blocks, tables). '
        'When referring to scanned content, always cite specific pages like [Page 1] or [Page 2]. '
        'If information is not present in the document, explicitly state that it was not found.';

    // Attached image takes priority
    if (attachedImages != null && attachedImages.isNotEmpty) {
      imageToSend = attachedImages.first;
    } else if (effectiveMode == 'currentPage' && doc != null && doc.pages.isNotEmpty) {
      final safeIdx = _currentPageIndex.clamp(0, doc.pages.length - 1);
      final page = doc.pages[safeIdx];
      final imgPath = page.processedImagePath ?? page.originalImagePath;
      if (imgPath != null && imgPath.isNotEmpty) {
        final f = File(imgPath);
        if (f.existsSync()) {
          imageToSend = f;
        }
      }
      promptToSend = 'Document: "${doc.title}" [Page ${safeIdx + 1} of ${doc.pageCount}]\n'
          'Question: $trimmedText\n'
          'Please inspect this scanned page and answer accurately.';
    } else if (effectiveMode == 'entireDoc' && doc != null) {
      final retrieved = _retrievalService.retrieveForQuery(
        document: doc,
        query: trimmedText,
        activePageIndex: _currentPageIndex,
      );
      promptToSend = '${retrieved.formattedContext}\n\nUser Question: $trimmedText';
      imageToSend = retrieved.primaryImageFile;
    }

    // 4. Stream response from Qwen3-VL-8B
    try {
      final stream = _hfService.streamChat(
        prompt: promptToSend,
        imageFile: imageToSend,
        systemPrompt: systemPrompt,
        onTick: (elapsed) {
          final remaining = (_hfService.remainingSecondsToday - elapsed).clamp(0, HfVisionService.dailyAllowanceSeconds);
          _liveRemainingOverride = remaining;
          notifyListeners();
        },
      );

      String accumulatedResponse = '';
      await for (final chunk in stream) {
        accumulatedResponse = chunk;
        _updateAssistantMessage(assistantMsgId, accumulatedResponse, isLoading: false);
      }

      if (accumulatedResponse.isEmpty) {
        _updateAssistantMessage(
          assistantMsgId,
          'No response was returned by the AI service. Please try again.',
          isLoading: false,
          hasError: true,
        );
      }
    } catch (e) {
      final errorMsg = _formatError(e);
      _errorMessage = errorMsg;
      _updateAssistantMessage(
        assistantMsgId,
        '⚠️ $errorMsg',
        isLoading: false,
        hasError: true,
      );
    } finally {
      _liveRemainingOverride = null;
      _isGenerating = false;
      await _hfService.initUsageTracking(forceRefresh: true);
      notifyListeners();
    }
  }

  void _updateAssistantMessage(String id, String content, {bool isLoading = false, bool hasError = false}) {
    final list = _conversations[_documentId];
    if (list == null) return;
    final idx = list.indexWhere((m) => m.id == id);
    if (idx != -1) {
      list[idx] = list[idx].copyWith(
        content: content,
        isLoading: isLoading,
        hasError: hasError,
      );
      notifyListeners();
    }
  }

  /// Cancels an ongoing generation.
  void stopGeneration() {
    if (!_isGenerating) return;
    _hfService.cancelGeneration();
    _isGenerating = false;
    _liveRemainingOverride = null;

    final list = _conversations[_documentId];
    if (list != null && list.isNotEmpty) {
      final lastMsg = list.last;
      if (lastMsg.role == MessageRole.assistant && lastMsg.isLoading) {
        list[list.length - 1] = lastMsg.copyWith(
          content: lastMsg.content.isEmpty ? 'Generation stopped by user.' : lastMsg.content,
          isLoading: false,
        );
      }
    }
    notifyListeners();
  }

  /// Retries the last failed user query.
  void retryLastMessage({Document? document}) {
    final list = _conversations[_documentId];
    if (list == null || list.isEmpty) return;

    // Find last user message
    final lastUserMsgIdx = list.lastIndexWhere((m) => m.role == MessageRole.user);
    if (lastUserMsgIdx == -1) return;

    final userPrompt = list[lastUserMsgIdx].content;

    // Remove any trailing failed assistant responses
    while (list.length > lastUserMsgIdx + 1) {
      list.removeLast();
    }
    list.removeAt(lastUserMsgIdx);
    notifyListeners();

    sendMessage(userPrompt, document: document);
  }

  /// Clears the conversation for the current document.
  void clearConversation() {
    _conversations[_documentId] = [];
    _errorMessage = null;
    notifyListeners();
  }

  /// Triggers a preset quick action.
  void triggerQuickAction(String actionType, {Document? document}) async {
    String userPrompt;
    switch (actionType) {
      case 'summarize':
        userPrompt = 'Provide a structured summary of this document with key bullet points and conclusions.';
        break;
      case 'explain':
        userPrompt = 'Explain the key concepts of this document simply so anyone can understand.';
        break;
      case 'extract':
        userPrompt = 'Extract all key facts, dates, amounts, tables, and important terms from this document.';
        break;
      case 'translate':
        userPrompt = 'Translate the core contents and key highlights of this document into Spanish.';
        break;
      case 'notes':
        userPrompt = 'Generate clear study notes, actionable takeaways, and a checklist from this document.';
        break;
      default:
        userPrompt = actionType;
    }

    await sendMessage(userPrompt, document: document);
  }

  String _formatError(dynamic e) {
    final str = e.toString();
    if (str.contains('SocketException') || str.contains('Failed host lookup')) {
      return 'Unable to connect to AI service. Check your internet connection.';
    }
    if (str.contains('TimeoutException')) {
      return 'Request timed out. The AI model may be waking up. Please retry.';
    }
    if (str.contains('503') || str.contains('504') || str.contains('busy')) {
      return 'The AI GPU Space is currently waking up or busy. Please retry in a moment.';
    }
    if (str.contains('Daily free allowance')) {
      return 'Daily free allowance reached (2 min / day). Resets at ${_hfService.resetTimeFormatted}.';
    }
    return str.replaceAll('Exception: ', '').replaceAll('HttpException: ', '');
  }
}
