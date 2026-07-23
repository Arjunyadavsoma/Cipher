import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:cipher_ai/core/services/groq/ai_pooling.dart';
import 'package:cipher_ai/core/services/groq/ai_provider.dart';
import 'package:cipher_ai/core/services/groq/chat_service.dart';

/// Extension on [ChatService] that adds multi-provider support.
/// The original [ChatService.sendMessage] is unchanged and still used
/// by internal agent systems (IntentGate, IntentClassifier, etc.).
extension ChatServiceProviderAddon on ChatService {
  /// Sends a message using the user-selected provider/model, with key
  /// rotation and success/failure reporting through
  /// [ProviderPoolService].
  Future<String> sendMessageToProvider({
    required AiProvider provider,
    required AiModel model,
    required String message,
    List<Map<String, String>> history = const [],
    String? systemPrompt,
    double temperature = 0.7,
  }) async {
    // Get the best available key (handles rotation, cooldowns, seeding).
    final apiKey = await ProviderPoolService.instance.getNextKey(provider);

    try {
      final result = await _callProviderUrl(
        url: provider.baseUrl,
        apiKey: apiKey,
        systemPrompt: systemPrompt ?? ChatService.defaultSystemPrompt,
        message: message,
        history: history,
        temperature: temperature,
        model: model.id,
        extraBody: model.supportsThinking
            ? const {
                'chat_template_kwargs': {
                  'enable_thinking': true,
                  'clear_thinking': false,
                },
              }
            : null,
      );
      await ProviderPoolService.instance.reportSuccess(provider, apiKey);
      return result;
    } on AiRequestException catch (e) {
      await ProviderPoolService.instance.reportFailure(
        provider,
        apiKey,
        error: e.message,
        statusCode: e.statusCode,
      );
      rethrow;
    } catch (e) {
      await ProviderPoolService.instance.reportFailure(
        provider,
        apiKey,
        error: e.toString(),
      );
      rethrow;
    }
  }

  /// Generic OpenAI-compatible /chat/completions call. Parameterized on
  /// URL and supports an optional `extra_body` for vendor-specific
  /// fields (e.g. NVIDIA's `chat_template_kwargs.enable_thinking`).
  Future<String> _callProviderUrl({
    required String url,
    required String apiKey,
    required String systemPrompt,
    required String message,
    required List<Map<String, String>> history,
    required String model,
    double temperature = 0.7,
    Map<String, dynamic>? extraBody,
  }) async {
    final messages = <Map<String, String>>[
      {"role": "system", "content": systemPrompt},
      ...history,
      {"role": "user", "content": message},
    ];

    final body = <String, dynamic>{
      "model": model,
      "temperature": temperature,
      "messages": messages,
      if (extraBody != null) "extra_body": extraBody,
    };

    final response = await http
        .post(
          Uri.parse(url),
          headers: {
            "Authorization": "Bearer $apiKey",
            "Content-Type": "application/json",
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      final errorMessage = _extractErrorMessage(response.body) ??
          "AI provider request failed (status ${response.statusCode})";
      throw AiRequestException(
        errorMessage,
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }

    final data;
    try {
      data = jsonDecode(response.body);
    } catch (_) {
      throw AiRequestException("Invalid JSON response from AI provider");
    }

    final content = data["choices"]?[0]?["message"]?["content"];
    if (content == null) {
      throw AiRequestException("Empty response from AI provider");
    }
    return content.toString();
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