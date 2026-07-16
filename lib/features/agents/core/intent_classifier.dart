import 'dart:convert';

import '../../../core/services/groq/chat_service.dart';
import 'agent_registry.dart';

class IntentClassificationResult {
  final String agentName;
  final double confidence;
  final String reason;

  const IntentClassificationResult({
    required this.agentName,
    required this.confidence,
    required this.reason,
  });
}

/// Stage 2 of routing: only runs once IntentGate has determined the
/// message needs a specialized agent. Builds the agent list dynamically
/// from AgentRegistry, so newly registered agents are automatically
/// eligible for selection with zero changes to this file.
class IntentClassifier {
  IntentClassifier._internal();

  static final IntentClassifier instance = IntentClassifier._internal();

  /// Dedicated system prompt for routing calls. The default ChatService
  /// persona ("professional assistant, give clear practical answers") was
  /// fighting the "JSON only" instruction below - this is why confidence
  /// 0.0 with an empty reason showed up: the model answered conversationally
  /// instead of emitting JSON, _extractJson found no braces, and the null
  /// coalescing silently produced agent='Default Chat Agent'/confidence=0.0
  /// with no exception thrown.
  static const String _routingSystemPrompt =
      "You are a routing classifier, not a conversational assistant. "
      "You only ever output a single JSON object matching the schema you "
      "are given. Never add explanation, caveats, or text outside the "
      "JSON object.";

  Future<IntentClassificationResult> classify(String message) async {
    final agents = AgentRegistry.instance.getAllAgents();

    final agentDescriptions =
        agents.map((a) => "${a.name}:\n${a.description}").join('\n\n');

    final prompt = "Available agents:\n\n$agentDescriptions\n\n"
        "Analyze:\n\"$message\"\n\n"
        "Return JSON only, no other text:\n"
        '{"agent":"<agent name>","confidence":0.0,"reason":"<short reason>"}';

    try {
      final response = await ChatService.instance.sendMessage(
        message: prompt,
        history: const [],
        systemPrompt: _routingSystemPrompt,
        temperature: 0.1,
      );

      final jsonStr = _extractJson(response);
      final parsed = jsonDecode(jsonStr) as Map<String, dynamic>;

      return IntentClassificationResult(
        agentName: parsed['agent'] ?? 'Default Chat Agent',
        confidence: (parsed['confidence'] as num?)?.toDouble() ?? 0.0,
        reason: parsed['reason'] ?? '',
      );
    } catch (_) {
      return const IntentClassificationResult(
        agentName: 'Default Chat Agent',
        confidence: 0.0,
        reason: 'Classification failed, defaulting.',
      );
    }
  }

  String _extractJson(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start == -1 || end == -1) return '{}';
    return text.substring(start, end + 1);
  }
}