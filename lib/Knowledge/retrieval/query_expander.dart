import 'dart:convert';
import 'package:cipher_ai/features/agents/core/tool_manager.dart';
import 'package:flutter/foundation.dart';

class QueryExpander {
  final _toolManager = ToolManager.instance;

  /// Expands a single query into multiple semantic variations and keywords.
  Future<List<String>> expandQuery(String userQuery) async {
    if (userQuery.trim().isEmpty) return [];

    final prompt = "User Query: \"$userQuery\"\n\n"
        "Generate 3 to 5 alternative search queries, synonyms, or specific sub-topics that would help find information about this query in a knowledge base. "
        "Output ONLY a JSON array of strings. Example: [\"alternative 1\", \"alternative 2\"]";

    try {
      final response = await _toolManager.executeTool('groq', {
        'systemPrompt': 'You are a search query expansion engine. Output ONLY a JSON array of strings.',
        'message': prompt,
        'temperature': 0.0,
      }) as String;

      final start = response.indexOf('[');
      final end = response.lastIndexOf(']');
      if (start == -1 || end == -1) return [userQuery];

      final List<dynamic> list = jsonDecode(response.substring(start, end + 1));
      // Always include the original query in the expanded list
      return [userQuery, ...list.map((e) => e.toString())];
    } catch (e) {
      debugPrint('QueryExpander failed: $e');
      return [userQuery]; // Fallback to just the original query
    }
  }
}