import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../core/tool_manager.dart';

class ResearchPlanner {
  final _toolManager = ToolManager.instance;

  Future<List<String>> createPlan(String userQuery) async {
    final prompt = "User wants to research: '$userQuery'\n\n"
        "Break this down into 6 to 8 specific search queries that will comprehensively cover the topic. "
        "You MUST include queries for:\n"
        "1. Background, early life, or history.\n"
        "2. Major achievements, positive impacts, and successes.\n"
        "3. Criticisms, controversies, failures, and negative aspects.\n"
        "4. Current status, recent news, and future outlook.\n"
        "5. Legacy and overall impact.\n\n"
        "Output ONLY a JSON array of strings. Example: [\"query 1\", \"query 2\"]";

    try {
      final response = await _toolManager.executeTool('groq', {
        'systemPrompt': 'You are a research planning assistant. Output ONLY a JSON array of strings.',
        'message': prompt,
        'temperature': 0.0,
      }) as String;

      final cleaned = _extractJson(response);
      final List<dynamic> list = jsonDecode(cleaned);
      return list.map((e) => e.toString()).toList();
    } catch (e) {
      debugPrint('ResearchPlanner failed: $e');
      return [userQuery];
    }
  }

  String _extractJson(String text) {
    final start = text.indexOf('[');
    final end = text.lastIndexOf(']');
    if (start == -1 || end == -1) return '[]';
    return text.substring(start, end + 1);
  }
}