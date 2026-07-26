import '../../../core/services/groq/chat_service.dart';
import '../models/tool.dart';

/// Wraps Groq API access.
///
/// This is the only entry point agents use to communicate with Groq.
/// API key selection, rotation, retry logic, cooldown handling, and
/// invalid-key quarantine are all handled internally by ChatService.
/// GroqTool simply forwards the request.
class GroqTool implements Tool {
  @override
  String get name => 'groq';

  /// Expected input:
  /// {
  ///   'systemPrompt': String,
  ///   'message': String,
  ///   'history': List<Map<String, String>>,
  ///   'useKeyPool': bool (optional, defaults to true)
  /// }
  @override
  Future<dynamic> execute(Map<String, dynamic> input) {
    final systemPrompt = input['systemPrompt'] as String? ?? '';
    final message = input['message'] as String? ?? '';
    final history =
        (input['history'] as List?)?.cast<Map<String, String>>() ??
            const <Map<String, String>>[];

    // Default to key rotation for all user-facing requests.
    // Internal services (IntentClassifier, ContextSummarizer, etc.)
    // can explicitly disable it if required.
    final useKeyPool = input['useKeyPool'] as bool? ?? true;

    if (useKeyPool) {
      return ChatService.instance.sendMessageWithKeyPool(
        message: message,
        systemPrompt: systemPrompt,
        history: history,
      );
    }

    // Legacy single-key path.
    return ChatService.instance.sendMessage(
      message: message,
      systemPrompt: systemPrompt,
      history: history,
    );
  }
}