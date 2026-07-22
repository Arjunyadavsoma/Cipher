// This file is meant to be merged into chat_service.dart - it's split out
// here so the diff against the existing file is easy to review. The
// method below (`sendMessageToProvider`) is the one new addition;
// `_callGroqUrl` is `_callGroq` generalized to take a URL and an
// optional extra_body instead of assuming Groq's fixed base URL, since
// ModelScope/Cerebras/NVIDIA NIM all speak the same request shape and
// only the URL (and, for NVIDIA's reasoning models, one extra field)
// differs.
//
// sendMessage() and sendMessageWithKey() are left completely alone -
// they still exist for the IntentGate/IntentClassifier/
// ContextSummarizerService callers described in the original file's
// docstring, which don't need provider selection.

import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:cipher_ai/core/services/groq/ai_pooling.dart';
import 'package:cipher_ai/core/services/groq/ai_provider.dart';
import 'package:cipher_ai/core/services/groq/chat_service.dart';

extension ChatServiceProviderAddon on ChatService {
  /// Sends a message using whichever provider/model the user has
  /// selected in settings, instead of the hardcoded Groq endpoint.
  /// Handles key rotation and success/failure reporting through
  /// ProviderPoolService, mirroring how the original sendMessage()
  /// implicitly used a single Groq key with no rotation.
  Future<String> sendMessageToProvider({
    required AiProvider provider,
    required AiModel model,
    required String message,
    List<Map<String, String>> history = const [],
    String? systemPrompt,
    double temperature = 0.7,
  }) async {
    // Inside sendMessageToProvider in the extension file:
// Replace: final apiKey = await ProviderPoolService.instance.getNextKey(provider);
// With:
final apiKey = dotenv.env[provider.apiKeyEnvVar] ?? '';
if (apiKey.isEmpty) throw Exception("API Key missing for ${provider.name}");
    try {
      final result = await _callProviderUrl(
        url: provider.baseUrl,
        apiKey: apiKey,
        systemPrompt: systemPrompt ?? ChatService.defaultSystemPrompt,
        message: message,
        history: history,
        temperature: temperature,
        model: model.id,
        // Only NVIDIA's reasoning-capable models (e.g. z-ai/glm-5.2)
        // use this extra_body shape today. Sending it to a provider
        // that doesn't understand it would likely just be ignored as
        // an unknown field, but it's gated on supportsThinking anyway
        // so the request body matches exactly what the user's NVIDIA
        // snippet sent for models that expect it.
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
    } catch (e) {
      await ProviderPoolService.instance.reportFailure(
        provider,
        apiKey,
        error: e.toString(),
      );
      rethrow;
    }
  }

  /// Same request/response handling as the private _callGroq in
  /// chat_service.dart, but parameterized on URL and with an optional
  /// extra_body passthrough. NOTE: the NVIDIA snippet the user pasted
  /// also set `top_p: 1`, `seed: 42`, and `stream: true`. `top_p: 1` is
  /// a no-op (it's the default) so it's omitted here. `seed: 42` is
  /// deliberately NOT carried over - a fixed seed would make every
  /// response for a given input deterministic-identical, which is
  /// almost certainly not what's wanted for a general chat feature; if
  /// reproducible output is ever needed for a specific screen, pass it
  /// explicitly there rather than hardcoding it into every request.
  /// `stream: true` is also not implemented here - see the note below
  /// on why streaming needs its own follow-up rather than folding it
  /// into this same call.
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

    try {
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
        final error = jsonDecode(response.body);
        throw Exception(
          error["error"]?["message"] ?? "AI provider request failed",
        );
      }

      final data = jsonDecode(response.body);
      final content = data["choices"]?[0]?["message"]?["content"];

      if (content == null) {
        throw Exception("Empty response from AI");
      }

      return content.toString();
    } catch (e) {
      throw Exception("AI service error: $e");
    }
  }
}
