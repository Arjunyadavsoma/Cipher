import 'dart:convert';
import 'package:cipher_ai/features/agents/core/tool_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:cipher_ai/Knowledge/knowledge_entry.dart';

class LlmReranker {
  final _toolManager = ToolManager.instance;

  /// Uses an LLM to critically evaluate and rerank candidates.
  Future<List<KnowledgeEntry>> rerank({
    required String query,
    required List<KnowledgeEntry> candidates,
    int topK = 5,
  }) async {
    if (candidates.length <= topK) return candidates;

    try {
      // Build a numbered list of candidates for the LLM to evaluate
      final buffer = StringBuffer();
      buffer.writeln("Query: $query\n\nCandidates:");
      for (int i = 0; i < candidates.length; i++) {
        buffer.writeln("${i + 1}. ${candidates[i].fact}");
      }

      final prompt = "Given the query and the list of candidate facts, select the TOP $topK facts that are MOST relevant to answering the query. "
          "Return a JSON array of integers representing their 1-based indices. Example: [1, 4, 5]\n\n${buffer.toString()}";

      final response = await _toolManager.executeTool('groq', {
        'systemPrompt': 'You are a relevance ranking engine. Output ONLY a JSON array of integers.',
        'message': prompt,
        'temperature': 0.0,
      }) as String;

      final start = response.indexOf('[');
      final end = response.lastIndexOf(']');
      if (start == -1 || end == -1) return candidates.take(topK).toList();

      final List<dynamic> indices = jsonDecode(response.substring(start, end + 1));
      
      final reranked = <KnowledgeEntry>[];
      for (final idx in indices) {
        final i = (idx as int) - 1;
        if (i >= 0 && i < candidates.length) {
          reranked.add(candidates[i]);
        }
      }
      
      return reranked.take(topK).toList();
    } catch (e) {
      debugPrint('LlmReranker failed, falling back to original order: $e');
      return candidates.take(topK).toList();
    }
  }
}