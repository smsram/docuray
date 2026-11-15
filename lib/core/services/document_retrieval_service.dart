import 'dart:io';
import '../../models/models.dart';

/// Represents retrieved context from a document for AI processing.
class RetrievedContext {
  final String formattedContext;
  final List<int> citedPages;
  final File? primaryImageFile;
  final String synopsis;

  const RetrievedContext({
    required this.formattedContext,
    required this.citedPages,
    this.primaryImageFile,
    required this.synopsis,
  });
}

/// Service that performs local indexing, chunking, and keyword/TF-IDF retrieval
/// across multi-page documents to provide targeted context to Qwen3-VL-8B.
class DocumentRetrievalService {
  static final DocumentRetrievalService instance = DocumentRetrievalService._internal();
  DocumentRetrievalService._internal();

  static const Set<String> _stopWords = {
    'a', 'an', 'and', 'are', 'as', 'at', 'be', 'by', 'for', 'from', 'has', 'he',
    'in', 'is', 'it', 'its', 'of', 'on', 'that', 'the', 'to', 'was', 'were',
    'will', 'with', 'what', 'when', 'where', 'which', 'who', 'why', 'how',
    'can', 'could', 'should', 'would', 'this', 'these', 'those', 'there',
    'then', 'than', 'tell', 'me', 'about', 'show', 'give', 'does', 'do',
  };

  /// Tokenizes text into lowercase word tokens, omitting common stop words.
  List<String> _tokenize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.length > 2 && !_stopWords.contains(t))
        .toList();
  }

  /// Evaluates whether the user query is intended for:
  /// - 'noDocument': purely generic query (e.g., "what is the capital of Italy")
  /// - 'entireDoc': document-level query (e.g., "summarize this file", "compare all pages")
  /// - 'currentPage': visual or page-specific query (e.g., "read this table", "page 1")
  String determineAutoMode({
    required String query,
    required Document document,
    required int currentPageIndex,
  }) {
    final lower = query.toLowerCase().trim();

    // Check for explicit document summary or multi-page keywords
    final summaryKeywords = [
      'summarize', 'summary', 'overview', 'outline', 'table of contents',
      'whole document', 'entire document', 'all pages', 'entire doc', 'full doc',
      'how many pages', 'compare', 'across the document', 'overall'
    ];
    for (final kw in summaryKeywords) {
      if (lower.contains(kw)) {
        return 'entireDoc';
      }
    }

    // Check for explicit page mentions (e.g., "page 2", "second page")
    final pagePattern = RegExp(r'\b(page|p\.)\s*(\d+)\b', caseSensitive: false);
    final match = pagePattern.firstMatch(lower);
    if (match != null) {
      return 'entireDoc';
    }

    // Check for document references
    final docKeywords = [
      'this document', 'the document', 'this scan', 'the scan', 'this pdf',
      'in here', 'this page', 'read this', 'what does this say', 'extract',
      'translate', 'explain this', 'transcribe', 'formula', 'handwriting',
      'signature', 'receipt', 'invoice', 'date', 'amount', 'total'
    ];
    for (final kw in docKeywords) {
      if (lower.contains(kw)) {
        return document.pageCount > 1 ? 'entireDoc' : 'currentPage';
      }
    }

    // Check if query mentions words from the document title
    final titleTokens = _tokenize(document.title);
    final queryTokens = _tokenize(query);
    final titleOverlap = queryTokens.where((t) => titleTokens.contains(t)).length;
    if (titleOverlap > 0) {
      return 'entireDoc';
    }

    // If query is generic general knowledge (e.g., "how far is the moon")
    final generalKnowledgeStarters = [
      'who is', 'what is', 'when was', 'where is', 'define', 'how to code',
      'write a poem', 'tell a joke', 'python code', 'flutter code'
    ];
    for (final starter in generalKnowledgeStarters) {
      if (lower.startsWith(starter) && !lower.contains('doc') && !lower.contains('page')) {
        return 'noDocument';
      }
    }

    // Default to currentPage for single page, entireDoc for multi-page
    return document.pageCount > 1 ? 'entireDoc' : 'currentPage';
  }

  /// Retrieves relevant sections and images across the document for a given query.
  RetrievedContext retrieveForQuery({
    required Document document,
    required String query,
    int? activePageIndex,
  }) {
    if (document.pages.isEmpty) {
      return const RetrievedContext(
        formattedContext: 'Document has no pages.',
        citedPages: [],
        synopsis: 'Empty document',
      );
    }

    final queryTokens = _tokenize(query);
    final Map<int, double> pageScores = {};
    final Map<int, List<String>> pageContentSnippets = {};

    // Explicit page number mention check
    int? explicitPageTarget;
    final pagePattern = RegExp(r'\b(?:page|p\.?)\s*(\d+)\b', caseSensitive: false);
    final match = pagePattern.firstMatch(query);
    if (match != null) {
      final requestedNum = int.tryParse(match.group(1)!);
      if (requestedNum != null && requestedNum >= 1 && requestedNum <= document.pageCount) {
        explicitPageTarget = requestedNum - 1;
      }
    }

    for (int i = 0; i < document.pages.length; i++) {
      final page = document.pages[i];
      final List<String> textPieces = [];

      // Include page number context
      textPieces.add('Page ${i + 1}');

      // Include text annotations on page
      for (final ann in page.annotations) {
        if (ann.text != null && ann.text!.trim().isNotEmpty) {
          textPieces.add(ann.text!.trim());
        }
      }

      // Include watermark text if configured
      if (page.watermark.enabled && page.watermark.text.isNotEmpty) {
        textPieces.add('Watermark: ${page.watermark.text}');
      }

      // Include OCR summary if present on document
      if (document.ocrSummary != null && document.ocrSummary!.isNotEmpty) {
        textPieces.add(document.ocrSummary!);
      }

      // Construct synopsis piece
      final pageDescription = 'Scanned page ${i + 1} (${page.filterType} filter, rotation ${page.rotationDegrees}°)';
      textPieces.add(pageDescription);

      final fullPageText = textPieces.join(' ');
      pageContentSnippets[i] = textPieces;

      // Calculate relevance score
      double score = 0.0;

      // Heavy boost if explicitly requested
      if (explicitPageTarget != null && explicitPageTarget == i) {
        score += 100.0;
      }

      // Slight boost for currently viewed page if no explicit page requested
      if (activePageIndex != null && activePageIndex == i) {
        score += 2.0;
      }

      final pageTokens = _tokenize(fullPageText);
      for (final qToken in queryTokens) {
        final occurrences = pageTokens.where((t) => t == qToken || t.contains(qToken)).length;
        if (occurrences > 0) {
          score += occurrences * 5.0;
        }
      }

      // Document title match boost
      final titleTokens = _tokenize(document.title);
      for (final tToken in titleTokens) {
        if (queryTokens.contains(tToken)) {
          score += 1.5;
        }
      }

      pageScores[i] = score;
    }

    // Sort pages by descending relevance
    final sortedPages = pageScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Select top pages (up to 3 pages)
    final topPages = sortedPages.take(3).map((e) => e.key).toList();
    if (topPages.isEmpty) {
      topPages.add(activePageIndex ?? 0);
    }

    // Build structured context string
    final buffer = StringBuffer();
    buffer.writeln('=== DOCUMENT CONTEXT: "${document.title}" ===');
    buffer.writeln('Total Pages: ${document.pageCount}');
    buffer.writeln('Created: ${document.createdAt.toLocal().toString().split('.').first}');
    buffer.writeln();
    buffer.writeln('--- RELEVANT PAGE SECTIONS ---');

    final List<int> citedPages = [];
    for (final pageIdx in topPages) {
      final pageNum = pageIdx + 1;
      citedPages.add(pageNum);
      buffer.writeln('[Page $pageNum]:');
      final snippets = pageContentSnippets[pageIdx] ?? [];
      for (final snip in snippets) {
        buffer.writeln('  • $snip');
      }
      buffer.writeln();
    }

    buffer.writeln('--- INSTRUCTIONS ---');
    buffer.writeln('Answer the user inquiry based on the scanned document contents above.');
    buffer.writeln('Always cite specific pages in brackets (e.g. [Page 1], [Page 2]) when referencing facts.');
    buffer.writeln('If the answer cannot be determined from the document, explicitly say so.');

    // Select primary image file for vision processing from the top relevant page
    File? primaryImage;
    final bestPageIdx = topPages.first;
    if (bestPageIdx < document.pages.length) {
      final bestPage = document.pages[bestPageIdx];
      final path = bestPage.processedImagePath ?? bestPage.originalImagePath;
      if (path != null && path.isNotEmpty) {
        final f = File(path);
        if (f.existsSync()) {
          primaryImage = f;
        }
      }
    }

    final synopsis = 'Indexed ${document.pageCount} pages · Focused on Page ${citedPages.join(', ')}';

    return RetrievedContext(
      formattedContext: buffer.toString(),
      citedPages: citedPages,
      primaryImageFile: primaryImage,
      synopsis: synopsis,
    );
  }
}

