import 'dart:convert';

import 'package:cipher_ai/Knowledge/knowledge_entry.dart';
import 'package:cipher_ai/features/agents/core/agent_registry.dart';

import '../../../core/services/groq/chat_service.dart';

import 'query_plan.dart';

/// Single classification call that replaces IntentGate + IntentClassifier.
/// One Groq call returns: which agent handles the message, required tags
/// for retrieval, new facts worth remembering, and old facts to forget.
class QueryPlannerService {
  QueryPlannerService._internal();

  static final QueryPlannerService instance = QueryPlannerService._internal();

  static const _routingSystemPrompt = '''
You are an AI routing engine.

Output exactly one JSON object. Never use markdown. Never explain.
Never write any text before or after the JSON.

Required schema:
{
  "agent": "string",
  "confidence": 0.0,
  "requiredKnowledgeTags": ["string"],
  "thingsToRemember": ["string"],
  "thingsToForget": ["string"],
  "query": "string"
}

CRITICAL RULES:
- "requiredKnowledgeTags" MUST be an array of 1-4 lowercase strings. Example: ["job", "work"]
- "thingsToRemember" MUST be an array of simple strings. Example: ["User works at Google"]
- "thingsToForget" MUST be an array of simple strings. Example: ["User works at Stripe"]
- DO NOT use nested objects.
- thingsToForget contains OLD facts that are now false or corrected. Write them as the exact short fact string.
''';

  Future<QueryPlan> plan(String message) async {
    final agents = AgentRegistry.instance.getAllAgents();
    final agentDescriptions = agents
        .map((a) => "${a.name}:\n${a.description}")
        .join('\n\n');

    final prompt = _buildPrompt(message, agentDescriptions);

    try {
      final response = await ChatService.instance.sendMessage(
        message: prompt,
        systemPrompt: _routingSystemPrompt,
        temperature: 0,
        model: "llama-3.1-8b-instant",
      );

      final jsonStr = _extractJson(response);
      final parsed = jsonDecode(jsonStr) as Map<String, dynamic>;

      return QueryPlan.fromJson(parsed, message);
    } catch (e) {
      // ignore: avoid_print
      print('QueryPlannerService.plan failed, using fallback: $e');
      return QueryPlan.fallback(message);
    }
  }

  String _buildPrompt(String message, String agentDescriptions) {
    final tagList = KnowledgeTaxonomy.allTags.map((t) => '"$t"').join(', ');

    return "Available agents:\n\n$agentDescriptions\n\n"
        "Analyze this message:\n\"$message\"\n\n"
        "Determine:\n"
        "1. Which agent should handle it (exact name match).\n"
        "2. Your confidence (0.0-1.0).\n"
        "3. requiredKnowledgeTags: 1-2 tags from this EXACT list: [$tagList]. "
        "If the user asks 'what projects am I working on', use [\"project\"]. "
        "If the user asks 'help me with graphs', use [\"dsa_topic\"]. "
        "If the user asks 'what's my email rule', use [\"email_rule\"].\n"
        "4. thingsToRemember: NEW facts as simple strings.ONLY extract permanent,long term facts about user. Example: [\"User is practicing Dynamic Programming for interviews\"]\n"
        "5. query: The user's cleaned request.\n\n"
        "Example:\n"
        "User says: 'I am prepping for DSA interviews using Grind 75.'\n"
        "{\"agent\":\"Default Chat Agent\",\"confidence\":0.9,\"requiredKnowledgeTags\":[\"interview_prep\",\"dsa_topic\"],\"thingsToRemember\":[\"User is prepping for DSA interviews using Grind 75\"],\"query\":\"I am prepping for DSA interviews using Grind 75.\"}\n\n"
        "Return JSON ONLY:";
  }

  /// Strips markdown code fences if the model wraps its output in them
  /// despite instructions not to, then extracts the {...} span.
  String _extractJson(String text) {
    var cleaned = text.trim();
    if (cleaned.startsWith('```')) {
      cleaned = cleaned
          .replaceFirst(RegExp(r'^```[a-zA-Z]*\n?'), '')
          .replaceFirst(RegExp(r'```\s*$'), '')
          .trim();
    }

    final start = cleaned.indexOf('{');
    final end = cleaned.lastIndexOf('}');
    if (start == -1 || end == -1 || end < start) {
      throw const FormatException('No JSON object found in response');
    }
    return cleaned.substring(start, end + 1);
  }
}
