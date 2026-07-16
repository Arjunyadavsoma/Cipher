import '../../../core/services/groq/chat_service.dart';

enum ChatIntent { normal, agentRequired }

/// Stage 1 of routing: a cheap, single-word classification that decides
/// whether the message needs full agent routing at all. Every message
/// that comes back NORMAL skips straight to the Default Chat Agent,
/// avoiding the extra cost of running the full IntentClassifier.
class IntentGate {
  IntentGate._internal();

  static final IntentGate instance = IntentGate._internal();

  /// Same rationale as IntentClassifier's _routingSystemPrompt: the
  /// conversational default persona was liable to make the model explain
  /// its answer instead of replying with exactly one word, and a rambling
  /// NORMAL explanation can easily contain the literal substring "agent"
  /// (e.g. "...no specialized agent needed"), which the old contains('AGENT')
  /// check would misread as ChatIntent.agentRequired.
  static const String _routingSystemPrompt =
      "You are a routing classifier, not a conversational assistant. "
      "You only ever output exactly the single word requested - never "
      "explanation, caveats, or extra text.";

  Future<ChatIntent> classify(String message) async {
    final prompt = "Classify this message as either NORMAL (casual "
        "conversation, greetings, simple questions, small talk) or AGENT "
        "(requires specialized help: coding/debugging, research/papers, "
        "writing emails, scheduling/calendar).\n\n"
        "Message: \"$message\"\n\n"
        "Reply with exactly one word: NORMAL or AGENT.";

    try {
      final response = await ChatService.instance.sendMessage(
        message: prompt,
        history: const [],
        systemPrompt: _routingSystemPrompt,
        temperature: 0.1,
      );

      final normalized = response.trim().toUpperCase();
      return normalized == 'AGENT' || normalized.startsWith('AGENT')
          ? ChatIntent.agentRequired
          : ChatIntent.normal;
    } catch (_) {
      // Fail-safe: if classification itself fails, don't block the user -
      // just treat it as normal chat.
      return ChatIntent.normal;
    }
  }
}