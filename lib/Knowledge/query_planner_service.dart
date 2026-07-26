import 'dart:convert';
import 'package:cipher_ai/features/agents/models/execution_context.dart';
import 'package:flutter/foundation.dart';
import 'package:cipher_ai/features/agents/core/agent_registry.dart';
import 'package:cipher_ai/Knowledge/query_plan.dart';
import '../../../core/services/groq/chat_service.dart';


/// Single classification call that determines agent routing and explicit
/// memory extraction (Remember/Forget).
class QueryPlannerService {
  QueryPlannerService._internal();
  static final QueryPlannerService instance = QueryPlannerService._internal();

  static const _routingSystemPrompt = '''
You are an AI routing and memory extraction engine for a multi-agent system.

Analyze the user's message IN THE CONTEXT OF THE CONVERSATION HISTORY.
- If the user is clearly continuing a topic handled by a specific agent (e.g., asking a follow-up question about an email draft, a DSA problem, or a research report), route to that SAME agent.
- If the user changes the subject entirely to something a specific agent handles, route to that specific agent.
- If the user asks a general question, or the request doesn't clearly fit a specialized agent, ALWAYS route to "Default Chat Agent". Do not force specialized agents if they aren't needed.

Output exactly one JSON object. Never use markdown. Never explain.
Never write any text before or after the JSON.

Required schema:
{
  "agent": "string",
  "confidence": 0.0,
  "thingsToRemember": ["string"],
  "thingsToForget": ["string"],
  "query": "string"
}

CRITICAL RULES:
- "agent": MUST be the exact name of an agent from the provided list. If unsure, use "Default Chat Agent".
- "thingsToRemember": MUST be an array of simple strings. ONLY extract permanent, long-term facts about the user. Example: ["User is preparing for DSA interviews using Grind 75"]
- "thingsToForget": MUST be an array of simple strings. Contains OLD facts that are now false or corrected. Example: ["User works at Stripe"]
- "query": The user's core intent, cleaned of unnecessary conversational fluff.
''';

  Future<QueryPlan> plan({
    required String message,
    required String rollingSummary,
    required List<ConversationMessage> recentMessages,
  }) async {
    final agents = AgentRegistry.instance.getAllAgents();
    final agentDescriptions = agents
        .map((a) => "${a.name}:\n${a.description}")
        .join('\n\n');

    final prompt = _buildPrompt(message, agentDescriptions, rollingSummary, recentMessages);

    try {
      final response = await ChatService.instance.sendMessage(
        message: prompt,
        systemPrompt: _routingSystemPrompt,
        temperature: 0,
        model: "llama-3.1-8b-instant",
      );

      final jsonStr = _extractJson(response);
      final parsed = jsonDecode(jsonStr) as Map<String, dynamic>;

      final validAgentNames = agents.map((a) => a.name).toSet();
      final plan = QueryPlan.fromJson(parsed, message, validAgentNames);

      return plan;
    } catch (e) {
      debugPrint('QueryPlannerService.plan failed, using fallback: $e');
      return QueryPlan.fallback(message);
    }
  }

  String _buildPrompt(
    String message,
    String agentDescriptions,
    String rollingSummary,
    List<ConversationMessage> recentMessages,
  ) {
    final historyText = recentMessages
        .map((m) => "${m.role}: ${m.content}")
        .join('\n');

    return "Available agents:\n\n$agentDescriptions\n\n"
        "Conversation Summary:\n$rollingSummary\n\n"
        "Recent History:\n$historyText\n\n"
        "Analyze this NEW message:\n\"$message\"\n\n"
        "Determine:\n"
        "1. Which agent should handle it (exact name match). If it's a general chat not related to any specialized agent, use 'Default Chat Agent'.\n"
        "2. Your confidence (0.0-1.0).\n"
        "3. thingsToRemember: Any NEW long-term facts learned about the user. Leave empty if none.\n"
        "4. thingsToForget: Any OLD facts that are contradicted by this message. Leave empty if none.\n"
        "5. query: The user's core request.\n\n"
        "Return JSON ONLY:";
  }

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