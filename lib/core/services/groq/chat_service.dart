import 'dart:convert';

import 'package:cipher_ai/core/services/groq/ai_provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class ChatService {
  ChatService._();
  static final ChatService instance = ChatService._();

  static const String _baseUrl =
      'https://api.groq.com/openai/v1/chat/completions';

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
        final errorMessage = _extractErrorMessage(response.body) ??
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