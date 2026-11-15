import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dedicated service for Hugging Face ZeroGPU Gradio API (Qwen3-VL-8B).
/// Handles multipart image upload with high-DPI resizing (< 1MB), chat stream queuing,
/// SSE streaming, active request cancellation, image caching, and daily free usage tracking (120s/day).
class HfVisionService {
  static final HfVisionService instance = HfVisionService._internal();
  HfVisionService._internal();

  static const String baseUrl = 'https://smsram-zerogpu.hf.space';
  static const int dailyAllowanceSeconds = 120; // 2 minutes per day

  static const String _keyDailyUsageSeconds = 'ai_daily_usage_seconds';
  static const String _keyDailyUsageDate = 'ai_usage_date';

  // Cache for uploaded image paths: localPath -> serverPath
  final Map<String, String> _uploadedImageCache = {};

  // Active streaming client for cancellation
  http.Client? _activeClient;
  bool _isCancelled = false;

  int _usedSecondsToday = 0;
  String _currentUsageDate = '';
  bool _usageInitialized = false;

  int get usedSecondsToday => _usedSecondsToday;
  int get remainingSecondsToday => (dailyAllowanceSeconds - _usedSecondsToday).clamp(0, dailyAllowanceSeconds);
  double get usageProgress => (_usedSecondsToday / dailyAllowanceSeconds).clamp(0.0, 1.0);
  bool get isAllowanceExhausted => _usedSecondsToday >= dailyAllowanceSeconds;

  String get resetTimeFormatted {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final diff = tomorrow.difference(now);
    final hours = diff.inHours;
    final mins = diff.inMinutes % 60;
    return '${hours}h ${mins}m (midnight)';
  }

  /// Initializes daily usage tracking from persistent storage.
  Future<void> initUsageTracking({bool forceRefresh = false}) async {
    final todayStr = _getTodayDateString();
    if (_usageInitialized && !forceRefresh && _currentUsageDate == todayStr) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedDate = prefs.getString(_keyDailyUsageDate) ?? '';

      if (savedDate == todayStr) {
        _usedSecondsToday = prefs.getInt(_keyDailyUsageSeconds) ?? 0;
      } else {
        // New calendar day: reset allowance
        _usedSecondsToday = 0;
        await prefs.setString(_keyDailyUsageDate, todayStr);
        await prefs.setInt(_keyDailyUsageSeconds, 0);
      }
      _currentUsageDate = todayStr;
      _usageInitialized = true;
    } catch (_) {
      _usageInitialized = true;
    }
  }

  String _getTodayDateString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _recordUsage(int elapsedSeconds) async {
    await initUsageTracking();
    final todayStr = _getTodayDateString();

    if (_currentUsageDate != todayStr) {
      _usedSecondsToday = 0;
      _currentUsageDate = todayStr;
    }

    _usedSecondsToday = (_usedSecondsToday + elapsedSeconds).clamp(0, dailyAllowanceSeconds * 2);

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyDailyUsageDate, todayStr);
      await prefs.setInt(_keyDailyUsageSeconds, _usedSecondsToday);
    } catch (_) {}
  }

  /// Cancels currently active generation request.
  void cancelGeneration() {
    _isCancelled = true;
    _activeClient?.close();
    _activeClient = null;
  }

  /// Uploads local image file and returns Gradio server file path.
  /// Automatically resizes/compresses high-DPI scans to < 1MB for fast uploads.
  /// Reuses cached server path if the same unchanged local file is provided.
  Future<String> uploadImage(File imageFile) async {
    final originalPath = imageFile.path;
    if (_uploadedImageCache.containsKey(originalPath)) {
      return _uploadedImageCache[originalPath]!;
    }

    File fileToUpload = imageFile;
    File? tempCompressedFile;

    try {
      final fileLength = await imageFile.length();
      // Compress if file is > 1MB or raw scan
      if (fileLength > 1024 * 1024) {
        final rawBytes = await imageFile.readAsBytes();
        final decoded = img.decodeImage(rawBytes);

        if (decoded != null) {
          img.Image resized = decoded;
          // Scale down high-DPI scans if dimension exceeds 1600px
          if (decoded.width > 1600 || decoded.height > 1600) {
            if (decoded.width >= decoded.height) {
              resized = img.copyResize(decoded, width: 1600);
            } else {
              resized = img.copyResize(decoded, height: 1600);
            }
          }

          final compressedBytes = img.encodeJpg(resized, quality: 82);
          final tempDir = await getTemporaryDirectory();
          tempCompressedFile = File('${tempDir.path}/ai_upload_${DateTime.now().millisecondsSinceEpoch}.jpg');
          await tempCompressedFile.writeAsBytes(compressedBytes);
          fileToUpload = tempCompressedFile;
        }
      }

      final uri = Uri.parse('$baseUrl/gradio_api/upload');
      final request = http.MultipartRequest('POST', uri)
        ..files.add(await http.MultipartFile.fromPath('files', fileToUpload.path));

      final streamedRes = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedRes);

      if (response.statusCode != 200) {
        throw HttpException('Image upload failed (${response.statusCode}): ${response.body}');
      }

      final List<dynamic> uploadedPaths = jsonDecode(response.body);
      if (uploadedPaths.isEmpty) {
        throw const FormatException('Empty upload response from Space.');
      }

      final serverPath = uploadedPaths.first as String;
      _uploadedImageCache[originalPath] = serverPath;
      return serverPath;
    } on SocketException {
      throw const SocketException('Unable to connect to AI service. Check your internet connection.');
    } on TimeoutException {
      throw TimeoutException('Image upload timed out. Please check connection and try again.');
    } finally {
      // Clean up temporary compressed file if created
      if (tempCompressedFile != null && tempCompressedFile.existsSync()) {
        try {
          tempCompressedFile.deleteSync();
        } catch (_) {}
      }
    }
  }

  /// Streams response chunks from Qwen3-VL-8B on ZeroGPU.
  /// Enforces daily usage limit and accurately tracks active generation time.
  Stream<String> streamChat({
    required String prompt,
    File? imageFile,
    String systemPrompt = 'You are DocuRay AI — an intelligent, concise, and document-aware assistant.',
    double temperature = 0.7,
    double topP = 0.8,
    int maxNewTokens = 512,
    void Function(int elapsedSeconds)? onTick,
  }) async* {
    await initUsageTracking();

    if (isAllowanceExhausted) {
      throw StateError(
        'Daily free allowance reached (2 min / day). Resets at $resetTimeFormatted.',
      );
    }

    _isCancelled = false;
    final stopwatch = Stopwatch()..start();
    Timer? liveTimer;

    if (onTick != null) {
      liveTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        onTick(stopwatch.elapsed.inSeconds);
      });
    }

    try {
      // 1. Upload image if provided
      final List<dynamic> filesPayload = [];
      if (imageFile != null) {
        try {
          final serverPath = await uploadImage(imageFile);
          filesPayload.add({
            'path': serverPath,
            'meta': {'_type': 'gradio.FileData'},
          });
        } on SocketException {
          throw const SocketException('Unable to connect to AI service. Check your internet connection.');
        } catch (e) {
          throw Exception('Failed to upload document image for AI analysis: $e');
        }
      }

      // 2. Queue chat request to Gradio Space
      final postUri = Uri.parse('$baseUrl/gradio_api/call/chat_stream');
      final body = jsonEncode({
        'data': [
          {'text': prompt, 'files': filesPayload},
          systemPrompt,
          temperature,
          topP,
          maxNewTokens < 64 ? 64 : maxNewTokens,
        ]
      });

      final client = http.Client();
      _activeClient = client;

      final postRes = await client.post(
        postUri,
        headers: {'Content-Type': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 25));

      if (_isCancelled) return;

      if (postRes.statusCode != 200) {
        if (postRes.statusCode == 503 || postRes.statusCode == 504) {
          throw const HttpException('The AI GPU Space is currently waking up or busy. Please retry in a moment.');
        }
        throw HttpException('Failed to queue request (${postRes.statusCode}): ${postRes.body}');
      }

      final dynamic postData = jsonDecode(postRes.body);
      final String? eventId = postData is Map ? postData['event_id'] as String? : null;

      if (eventId == null) {
        throw const FormatException('Missing event_id in Gradio queue response.');
      }

      // 3. Stream Server-Sent Events (SSE)
      final getUri = Uri.parse('$baseUrl/gradio_api/call/chat_stream/$eventId');
      final sseRequest = http.Request('GET', getUri);
      final sseResponse = await client.send(sseRequest);

      String currentEvent = '';
      String lastYielded = '';

      await for (final line in sseResponse.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (_isCancelled) break;

        final trimmed = line.trim();
        if (trimmed.startsWith('event:')) {
          currentEvent = trimmed.substring(6).trim();
        } else if (trimmed.startsWith('data:')) {
          final rawData = trimmed.substring(5).trim();

          if (currentEvent == 'generating' || currentEvent == 'complete') {
            try {
              final parsed = jsonDecode(rawData);
              if (parsed is List && parsed.isNotEmpty && parsed[0] != null) {
                final accumulatedText = parsed[0].toString();
                if (accumulatedText.isNotEmpty && accumulatedText != lastYielded) {
                  lastYielded = accumulatedText;
                  yield accumulatedText;
                }
              }
            } catch (_) {}
          } else if (currentEvent == 'error') {
            throw Exception('ZeroGPU Error: $rawData');
          }
        }
      }
    } on SocketException {
      throw const SocketException('Unable to connect to AI service. Check your internet connection.');
    } on TimeoutException {
      throw TimeoutException('AI request timed out. Please check your connection and retry.');
    } finally {
      liveTimer?.cancel();
      stopwatch.stop();
      final elapsedSecs = stopwatch.elapsed.inSeconds;
      if (elapsedSecs > 0) {
        await _recordUsage(elapsedSecs);
      }
      _activeClient?.close();
      _activeClient = null;
    }
  }
}
