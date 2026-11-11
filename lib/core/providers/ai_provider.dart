import 'package:flutter/material.dart';
import '../../models/models.dart';

/// Provider for contextual Document AI Assistant.
class AiProvider extends ChangeNotifier {
  String _documentId = '';
  String _documentTitle = '';
  int _documentPageCount = 1;

  final Map<String, List<AIMessage>> _conversations = {};
  bool _isThinking = false;
  String? _errorMessage;

  String get documentId => _documentId;
  String get documentTitle => _documentTitle;
  int get documentPageCount => _documentPageCount;
  bool get isThinking => _isThinking;
  String? get errorMessage => _errorMessage;

  List<AIMessage> get messages => _conversations[_documentId] ?? [];

  void setDocumentContext({
    required String documentId,
    required String title,
    required int pageCount,
  }) {
    _documentId = documentId;
    _documentTitle = title;
    _documentPageCount = pageCount;
    _errorMessage = null;

    // Provide initial sample contextual conversation if none exists
    if (!_conversations.containsKey(documentId)) {
      _conversations[documentId] = [
        AIMessage(
          id: 'welcome_msg',
          role: MessageRole.assistant,
          content: 'I have analyzed $title ($pageCount ${pageCount == 1 ? 'page' : 'pages'}). You can ask questions about formulas, key concepts, or tap a quick action below.',
          timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
        ),
      ];
    }
    notifyListeners();
  }

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    final userMessage = AIMessage(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
      role: MessageRole.user,
      content: text.trim(),
      timestamp: DateTime.now(),
    );

    _conversations.putIfAbsent(_documentId, () => []);
    _conversations[_documentId]!.add(userMessage);
    _isThinking = true;
    _errorMessage = null;
    notifyListeners();

    // Calm preview response simulation
    await Future.delayed(const Duration(milliseconds: 1200));

    final assistantResponse = AIMessage(
      id: 'resp_${DateTime.now().millisecondsSinceEpoch}',
      role: MessageRole.assistant,
      content: _generateSampleResponse(text),
      timestamp: DateTime.now(),
    );

    _conversations[_documentId]!.add(assistantResponse);
    _isThinking = false;
    notifyListeners();
  }

  void triggerQuickAction(String actionType) async {
    String userPrompt;
    switch (actionType) {
      case 'summarize':
        userPrompt = 'Summarize this document';
        break;
      case 'explain':
        userPrompt = 'Explain the key concepts simply';
        break;
      case 'extract':
        userPrompt = 'Extract key data, dates, and terms';
        break;
      case 'translate':
        userPrompt = 'Translate summary to Spanish';
        break;
      case 'notes':
        userPrompt = 'Create study notes and bullet points';
        break;
      default:
        userPrompt = actionType;
    }

    await sendMessage(userPrompt);
  }

  void retryLastMessage() {
    if (messages.isEmpty) return;
    final lastUserMsg = messages.lastWhere((m) => m.role == MessageRole.user, orElse: () => messages.last);
    sendMessage(lastUserMsg.content);
  }

  void clearConversation() {
    _conversations[_documentId] = [];
    notifyListeners();
  }

  String _generateSampleResponse(String prompt) {
    final lower = prompt.toLowerCase();
    if (lower.contains('summarize') || lower.contains('summary')) {
      return '### Summary of $_documentTitle\n\n'
          '• **Primary Topic:** The document covers foundational principles and structured formulas across $_documentPageCount pages.\n'
          '• **Core Concepts:** Outlines key methodologies, analytical derivations, and empirical observation tables.\n'
          '• **Conclusion:** Highlights experimental verification and final action items.\n\n'
          '*Note: This is a preview demonstration of DocuRay\'s upcoming Gemini AI assistant.*';
    } else if (lower.contains('explain') || lower.contains('simply')) {
      return '### Key Concepts Explained Simply\n\n'
          '1. **Core Problem:** The document introduces foundational mechanisms step by step without unnecessary jargon.\n'
          '2. **Working Principle:** Each section builds directly on prior observations, making it easy to review in small study increments.\n'
          '3. **Practical Takeaway:** Key findings are grouped at the bottom of each page for quick recall.';
    } else if (lower.contains('extract')) {
      return '### Extracted Terms & Data\n\n'
          '• **Title:** $_documentTitle\n'
          '• **Pages:** $_documentPageCount pages\n'
          '• **Key Terms:** Formulas, Derivations, Theorem proofs, Empirical readings\n'
          '• **Status:** Cleanly scanned and digitized in DocuRay';
    } else if (lower.contains('translate')) {
      return '### Resumen en Español\n\n'
          'Este documento ($_documentTitle) contiene notas detalladas estructuradas en $_documentPageCount páginas con conceptos fundamentales y fórmulas clave.';
    } else if (lower.contains('notes')) {
      return '### Study Notes\n\n'
          '✓ Review section headers on pages 1–3 for exam definitions.\n'
          '✓ Pay special attention to highlighted formulas.\n'
          '✓ Practice numerical questions listed in the appendix.';
    }

    return 'Based on the scanned pages of **$_documentTitle**, the text discusses the main points regarding your query. When connected to Gemini in Phase 2, this will extract full multi-modal insights directly from your digitized document.';
  }
}
