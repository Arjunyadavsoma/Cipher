import 'agent_registry.dart';
import 'base_agent.dart';

/// What's left of AgentRouter after QueryPlannerService took over
/// routing: just the explicit @mention check. This stays separate from
/// the planner because a mention is a hard, deterministic override -
/// the user explicitly said "@video", so no LLM call should be able to
/// override that, the same way it couldn't override it under the old
/// IntentGate/IntentClassifier flow either.
class AgentRouter {
  AgentRouter._internal();
  static final AgentRouter instance = AgentRouter._internal();

  BaseAgent? findMentionedAgent(String message) {
    final lowerMessage = message.toLowerCase();

    if (lowerMessage.contains('@image')) {
      return AgentRegistry.instance.getAgent('pixelster_image');
    }
    // Inside agent_router.dart
    if (lowerMessage.contains('@mock')) {
      return AgentRegistry.instance.getAgent('interview_agent');
    }
    
    if (lowerMessage.contains('@video')) {
      return AgentRegistry.instance.getAgent('pixelster_video');
    }

    if (lowerMessage.contains('@dsa')) {
      return AgentRegistry.instance.getAgent('dsa_agent');
    }

    // ADD THIS NEW BLOCK FOR INTERVIEW AGENT:
    if (lowerMessage.contains('@interview')) {
      return AgentRegistry.instance.getAgent('interview_agent');
    }
    if (lowerMessage.contains('@research')) {
      return AgentRegistry.instance.getAgent('research_agent');
    }

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