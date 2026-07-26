import 'dart:convert';

import 'package:cipher_ai/core/services/groq/ai_provider.dart';
import 'package:cipher_ai/features/agents/services/api_key_pool_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class ChatService {
  ChatService._();
  static final ChatService instance = ChatService._();

  static const String _baseUrl =
      'https://api.groq.com/openai/v1/chat/completions';

  // Caps how many different keys sendMessageWithKeyPool will try before
  // giving up. Bounded rather than "try every key in the pool" so a large
  // pool (the .env comment above _keys mentions ~30 keys eventually)
  // can't turn one bad burst into 30 sequential failed requests.
  static const int _maxKeyPoolAttempts = 5;

  static const String _defaultSystemPrompt = """
You are Mimir AI.

You are a professional AI assistant.
Help users with:
- Programming
- AI and ML
- Research
- Productivity
- Planning
- Learning
- Daily tasks

Give clear, accurate and practical answers.
""";

  static const String defaultSystemPrompt = _defaultSystemPrompt;

  /// Used internally by the agent system (IntentGate, IntentClassifier,
  /// ContextSummarizerService) for lightweight utility calls that don't
  /// need key rotation. Always uses the single .env key directly.
  Future<String> sendMessage({
    required String message,
    List<Map<String, String>> history = const [],
    String? systemPrompt,
    double temperature = 0.7,
    String model = "llama-3.3-70b-versatile",
  }) async {
    final apiKey = dotenv.env["GROQ_API_KEY"];
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception("Missing GROQ_API_KEY");
    }
    return _callGroq(
      apiKey: apiKey,
      systemPrompt: systemPrompt ?? _defaultSystemPrompt,
      message: message,
      history: history,
      temperature: temperature,
      model: model,
    );
  }

  Future<String> sendMessageWithKey({
    required String apiKey,
    required String systemPrompt,
    required String message,
    List<Map<String, String>> history = const [],
    double temperature = 0.7,
    String model = "llama-3.3-70b-versatile",
  }) async {
    if (apiKey.isEmpty) {
      throw Exception("Empty API key");
    }
    return _callGroq(
      apiKey: apiKey,
      systemPrompt: systemPrompt,
      message: message,
      history: history,
      temperature: temperature,
      model: model,
    );
  }

  /// Main entry point for the agent system's real (non-utility) calls -
  /// e.g. the 'groq' tool that DefaultChatAgent and other user-facing
  /// agents run through ToolManager. Every call pulls the least-used
  /// available key from [ApiKeyPoolService], reports the outcome back to
  /// the pool, and - only when the failure was a rate limit or an
  /// invalid/revoked key - retries with the next least-used key instead of
  /// failing the user's request outright. Any other kind of error (a
  /// network issue, a malformed response, a Groq-side outage) is rethrown
  /// immediately, since a different key wouldn't change that outcome.
  ///
  /// Wherever the 'groq' tool currently calls [sendMessage], point it at
  /// this method instead - same parameters, drop-in replacement. Leave
  /// [sendMessage] itself untouched; it's still what IntentGate,
  /// IntentClassifier, and ContextSummarizerService should use.
  Future<String> sendMessageWithKeyPool({
    required String message,
    List<Map<String, String>> history = const [],
    String? systemPrompt,
    double temperature = 0.7,
    String model = "llama-3.3-70b-versatile",
  }) async {
    final pool = ApiKeyPoolService.instance;
    final triedKeys = <String>{};
    AiRequestException? lastError;

    // Bound attempts by how many distinct keys actually exist (floor of 1
    // so a single-key setup still gets its one attempt), capped at
    // _maxKeyPoolAttempts so a big pool can't mean a long chain of
    // sequential failures before the user sees an error.
    final keyCount = pool.keyCount;
    final maxAttempts = keyCount < 1
        ? 1
        : (keyCount < _maxKeyPoolAttempts ? keyCount : _maxKeyPoolAttempts);

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final key = await pool.getNextKey();

      // Every distinct key has already been tried this call (the pool
      // recycles keys once all of them are quarantined) - one more loop
      // would just repeat a failure already reported, so stop here.
      if (!triedKeys.add(key)) break;

      try {
        final result = await _callGroq(
          apiKey: key,
          systemPrompt: systemPrompt ?? _defaultSystemPrompt,
          message: message,
          history: history,
          temperature: temperature,
          model: model,
        );
        await pool.reportSuccess(key);
        return result;
      } on AiRequestException catch (e) {
        lastError = e;
        final wasKeyIssue = await pool.reportFailure(key, error: e.message);
        if (!wasKeyIssue) rethrow;
        // Otherwise loop - getNextKey() will hand back the next
        // least-used, non-quarantined key on the next iteration.
      }
    }

    throw lastError ?? AiRequestException("No Groq API keys available to try");
  }

  Future<String> _callGroq({
    required String apiKey,
    required String systemPrompt,
    required String message,
    required List<Map<String, String>> history,
    required String model,
    double temperature = 0.7,
  }) async {
    final messages = <Map<String, String>>[
      {"role": "system", "content": systemPrompt},
      ...history,
      {"role": "user", "content": message},
    ];

    try {
      final response = await http
          .post(
            Uri.parse(_baseUrl),
            headers: {
              "Authorization": "Bearer $apiKey",
              "Content-Type": "application/json",
            },
            body: jsonEncode({
              "model": model,
              "temperature": temperature,
              "messages": messages,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        final errorMessage =
            _extractErrorMessage(response.body) ??
            "Groq API request failed (status ${response.statusCode})";
        throw AiRequestException(
          errorMessage,
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      }

      final data = jsonDecode(response.body);
      final content = data["choices"]?[0]?["message"]?["content"];
      if (content == null) {
        throw AiRequestException("Empty response from AI");
      }
      return content.toString();
    } on AiRequestException {
      rethrow;
    } catch (e) {
      throw AiRequestException("AI service error: $e");
    }
  }

  String? _extractErrorMessage(String body) {
    try {
      final error = jsonDecode(body);
      return error["error"]?["message"];
    } catch (_) {
      return null;
    }
  }
}
