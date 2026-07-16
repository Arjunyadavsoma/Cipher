import 'package:mimir_ai/features/agents/built_in/news_agent.dart';
import 'package:mimir_ai/features/agents/research_agent/research_agent.dart';

import '../built_in/default_chat_agent.dart';
import '../built_in/email_agent.dart';
import 'base_agent.dart';

/// Central registry of all agents. The router and executor only ever
/// go through this class - they never import DsaAgent, ResearchAgent,
/// etc. directly. To add a new agent: create the class, register it
/// in the constructor below, done.
class AgentRegistry {
  AgentRegistry._internal() {
    registerAgent(DefaultChatAgent());
    registerAgent(EmailAgent());
    registerAgent(NewsAgent()); 
    registerAgent(ResearchAgent()); 

    
    // Future agents get registered here, one line each, e.g.:
    // registerAgent(DsaAgent());
    // registerAgent(ResearchAgent());
    // registerAgent(CalendarAgent());
  }

  static final AgentRegistry instance = AgentRegistry._internal();

  final Map<String, BaseAgent> _agents = {};

  void registerAgent(BaseAgent agent) {
    _agents[agent.id] = agent;
  }

  BaseAgent? getAgent(String id) => _agents[id];

  /// Case-insensitive lookup by display name - used both for @mention
  /// resolution and for matching the LLM classifier's JSON output.
  BaseAgent? findByName(String name) {
    final normalized = name.trim().toLowerCase();
    for (final agent in _agents.values) {
      if (agent.name.toLowerCase() == normalized) return agent;
    }
    return null;
  }

  List<BaseAgent> getAllAgents() => _agents.values.toList();

  BaseAgent get defaultAgent => _agents['default_chat']!;
}
