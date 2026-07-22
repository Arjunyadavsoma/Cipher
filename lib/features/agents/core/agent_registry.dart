import 'package:cipher_ai/features/agents/DSA_agent/dsa_agent.dart';
import 'package:cipher_ai/features/agents/built_in/news_agent.dart';
import 'package:cipher_ai/features/agents/interview_agent/interview_agent.dart';
import 'package:cipher_ai/features/agents/research_agent/research_agent.dart';
import 'package:cipher_ai/features/pixelster/agents/image_agent.dart';
import 'package:cipher_ai/features/pixelster/agents/video_agent.dart';

import '../built_in/default_chat_agent.dart';
import '../built_in/email_agent.dart';
import 'base_agent.dart';

class AgentRegistry {
  AgentRegistry._internal() {
    registerAgent(DefaultChatAgent());
    registerAgent(EmailAgent());
    registerAgent(NewsAgent());
    registerAgent(ResearchAgent());
    registerAgent(DsaAgent());
    registerAgent(InterviewAgent());

    // Register Snapgen Agents
    registerAgent(ImageAgent());
    registerAgent(VideoAgent());
  }

  static final AgentRegistry instance = AgentRegistry._internal();

  final Map<String, BaseAgent> _agents = {};

  void registerAgent(BaseAgent agent) {
    _agents[agent.id] = agent;
  }

  BaseAgent? getAgent(String id) => _agents[id];

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
