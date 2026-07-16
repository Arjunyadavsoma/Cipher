import '../../../core/services/groq/chat_service.dart';
import '../models/tool.dart';
import '../services/api_key_pool_service.dart';

/// Wraps Groq API access. This is the ONLY place agents indirectly reach
/// the Groq API - always through ToolManager.executeTool('groq', ...).
/// Key rotation/selection is fully hidden inside this tool.
class GroqTool implements Tool {
  @override
  String get name => 'groq';

  final ApiKeyPoolService _keyPool = ApiKeyPoolService.instance;

  /// Caps retries so a fully-dead pool (every key invalid/rate-limited)
  /// fails after a bounded number of attempts instead of looping. Doesn't
  /// need to match the pool size exactly - 3 is enough to route around
  /// one or two bad keys without turning a single request into a dozen
  /// Groq calls if something is more broadly wrong.
  static const _maxAttempts = 3;

  /// Expected input:
  /// {
  ///   'systemPrompt': String,
  ///   'message': String,
  ///   'history': List<Map<String, String>>,
  /// }
  @override
  Future<dynamic> execute(Map<String, dynamic> input) async {
    final systemPrompt = input['systemPrompt'] as String? ?? '';
    final message = input['message'] as String? ?? '';
    final history =
        (input['history'] as List?)?.cast<Map<String, String>>() ?? const [];

    Object? lastError;

    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      final apiKey = await _keyPool.getNextKey();

      try {
        final response = await ChatService.instance.sendMessageWithKey(
          apiKey: apiKey,
          systemPrompt: systemPrompt,
          message: message,
          history: history,
        );

        await _keyPool.reportSuccess(apiKey);
        return response;
      } catch (e) {
        lastError = e;
        await _keyPool.reportFailure(apiKey, error: e.toString());
        // Loop continues - getNextKey() will skip this key now that
        // reportFailure() has quarantined/cooled it down, so the next
        // iteration picks a different one rather than retrying the same
        // dead key.
      }
    }

    // Every attempt failed - surface the last real error rather than a
    // generic "all retries exhausted" message, so callers (and
    // ResearchAgent/EmailAgent's own error handling) still see the
    // actual Groq failure reason.
    throw Exception(
      'Groq call failed after $_maxAttempts attempt(s): $lastError',
    );
  }
}