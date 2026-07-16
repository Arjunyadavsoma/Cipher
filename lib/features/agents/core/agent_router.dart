import 'agent_registry.dart';
import 'base_agent.dart';
import 'intent_classifier.dart';
import 'intent_gate.dart';

class RoutingDecision {
  final BaseAgent agent;

  /// 'mention' | 'normal' | 'classified' | 'default'
  final String method;
  final double confidence;

  const RoutingDecision({
    required this.agent,
    required this.method,
    this.confidence = 1.0,
  });
}

/// Routing priority, exactly per spec:
///   1. Explicit @mention -> direct match, execute immediately
///   2. No mention -> IntentGate decides normal vs agent-required
///   3. If agent-required -> IntentClassifier picks a specific agent
///   4. Confidence >= 0.80 -> use selected agent
///      Confidence <  0.80 -> fall back to Default Chat Agent
class AgentRouter {
  AgentRouter._internal();

  static final AgentRouter instance = AgentRouter._internal();

  static const double _confidenceThreshold = 0.80;

  Future<RoutingDecision> route(String message) async {
    // Step 1: explicit @mention - check the message against every
    // registered agent's actual name (longest names first, so e.g.
    // "Email Agent" is checked before any shorter/partial name that
    // could otherwise match a prefix of it).
    final mentionAgent = _findMentionedAgent(message);
    if (mentionAgent != null) {
      // ignore: avoid_print
      print('AgentRouter: matched @mention -> ${mentionAgent.name}');
      return RoutingDecision(agent: mentionAgent, method: 'mention');
    }

    // Step 2: cheap normal-vs-agent gate
    final intent = await IntentGate.instance.classify(message);
    if (intent == ChatIntent.normal) {
      return RoutingDecision(
        agent: AgentRegistry.instance.defaultAgent,
        method: 'normal',
      );
    }

    // Step 3: full agent classification
    final classification = await IntentClassifier.instance.classify(message);

    // ignore: avoid_print
    print('AgentRouter: classifier picked "${classification.agentName}" '
        'at confidence ${classification.confidence} '
        '(reason: "${classification.reason}")');

    if (classification.confidence >= _confidenceThreshold) {
      final agent =
          AgentRegistry.instance.findByName(classification.agentName);
      if (agent != null) {
        return RoutingDecision(
          agent: agent,
          method: 'classified',
          confidence: classification.confidence,
        );
      }
    }

    // Step 4: low confidence or unmatched agent name -> safe fallback
    return RoutingDecision(
      agent: AgentRegistry.instance.defaultAgent,
      method: 'default',
      confidence: classification.confidence,
    );
  }

  /// Checks whether "@<agent name>" (case-insensitive) appears anywhere in
  /// the message, for every registered agent. Checks longer names first so
  /// a shorter agent name that happens to be a prefix of a longer one
  /// can't shadow it.
  BaseAgent? _findMentionedAgent(String message) {
    final lowerMessage = message.toLowerCase();

    final agents = AgentRegistry.instance.getAllAgents().toList()
      ..sort((a, b) => b.name.length.compareTo(a.name.length));

    for (final agent in agents) {
      final mentionText = '@${agent.name}'.toLowerCase();
      if (lowerMessage.contains(mentionText)) {
        return agent;
      }
    }

    return null;
  }
}