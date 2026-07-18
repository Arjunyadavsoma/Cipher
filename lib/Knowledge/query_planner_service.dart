import 'dart:convert';

import 'package:mimir_ai/features/agents/core/agent_registry.dart';

import '../../../core/services/groq/chat_service.dart';

import 'query_plan.dart';

/// Replaces IntentGate + IntentClassifier with a single classification
/// call. Same latency budget as the old two-call flow, but the model
/// also returns which knowledge tags are relevant and what new facts
/// (if any) are worth remembering - both previously separate concerns
/// (ContextSummarizerService.isMemoryTrigger did memory detection with
/// a keyword list; this folds that into the same call as routing).
class QueryPlannerService {
  QueryPlannerService._internal();

  static final QueryPlannerService instance = QueryPlannerService._internal();

  static const String _routingSystemPrompt =
      "You are a routing and knowledge-planning classifier, not a "
      "conversational assistant. You only ever output a single JSON "
      "object matching the schema you are given. Never add explanation, "
      "caveats, or text outside the JSON object.";

  Future<QueryPlan> plan(String message) async {
    final agents = AgentRegistry.instance.getAllAgents();
    final agentDescriptions =
        agents.map((a) => "${a.name}:\n${a.description}").join('\n\n');

    final prompt = _buildPrompt(message, agentDescriptions);

    try {
      final response = await ChatService.instance.sendMessage(
        message: prompt,
        history: const [],
        systemPrompt: _routingSystemPrompt,
        temperature: 0.1,
      );

      final jsonStr = _extractJson(response);
      final parsed = jsonDecode(jsonStr) as Map<String, dynamic>;

      return QueryPlan.fromJson(parsed, message);
    } catch (_) {
      return QueryPlan.fallback(message);
    }
  }

  String _buildPrompt(String message, String agentDescriptions) {
    return "Available agents:\n\n$agentDescriptions\n\n"
        "Available knowledge layers: personal, professional, preferences, "
        "technical, projects, general.\n\n"
        "Analyze this message:\n\"$message\"\n\n"
        "Determine:\n"
        "1. Which agent should handle it (by exact name).\n"
        "2. Your confidence (0.0-1.0).\n"
        "3. Which short knowledge tags (single words or short phrases, "
        "e.g. \"job\", \"email_style\", \"diet\") would help answer this - "
        "empty list if none needed.\n"
        "4. Any new facts stated in this message worth remembering "
        "long-term, written as short standalone sentences - empty list "
        "if nothing new/memorable was said. Do NOT invent facts.\n"
        "5. The user's query, lightly cleaned of filler if needed "
        "(otherwise just repeat it).\n\n"
        "Return JSON only, no other text, in this exact shape:\n"
        '{"agent":"<agent name>","confidence":0.0,'
        '"requiredKnowledgeTags":["tag1","tag2"],'
        '"thingsToRemember":["fact1"],'
        '"query":"<cleaned query>"}';
  }

  String _extractJson(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start == -1 || end == -1) return '{}';
    return text.substring(start, end + 1);
  }
}
