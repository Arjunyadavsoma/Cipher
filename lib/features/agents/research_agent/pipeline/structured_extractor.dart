import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../core/tool_manager.dart';

class StructuredExtractor {
  final _toolManager = ToolManager.instance;

  /// Extracts structured facts from text chunks.
  Future<List<Map<String, dynamic>>> extract(String topic, List<Map<String, String>> chunks) async {
    final allFacts = <Map<String, dynamic>>[];
    
    // Process chunks in parallel (batches of 3 to avoid rate limits)
    for (int i = 0; i < chunks.length; i += 3) {
      final batch = chunks.sublist(i, i + 3 > chunks.length ? chunks.length : i + 3);
      final futures = batch.map((c) => _extractFromChunk(topic, c));
      final results = await Future.wait(futures);
      
      for (final factList in results) {
        allFacts.addAll(factList);
      }
    }
    return allFacts;
  }

  Future<List<Map<String, dynamic>>> _extractFromChunk(String topic, Map<String, String> chunk) async {
    final prompt = "Research Topic: $topic\n\nSource: ${chunk['title']} (${chunk['url']})\n\nContent:\n${chunk['text']}\n\n"
        "Extract key facts, definitions, code snippets, or data points relevant to the topic. "
        "Return a JSON array of objects with keys: 'fact' (string), 'category' (string).";

    try {
      final res = await _toolManager.executeTool('groq', {
        'systemPrompt': 'You are an information extraction engine. Output ONLY a valid JSON array. No markdown.',
        'message': prompt,
        'temperature': 0.0,
      }) as String;

      final start = res.indexOf('[');
      final end = res.lastIndexOf(']');
      if (start == -1 || end == -1) return [];

      final List<dynamic> list = jsonDecode(res.substring(start, end + 1));
      return list.map((f) {
        final map = f as Map<String, dynamic>;
        return {
          'fact': map['fact'] ?? '',
          'category': map['category'] ?? 'general',
          'source': chunk['url'],
        };
      }).toList();
    } catch (e) {
      debugPrint('Extraction failed: $e');
      return [];
    }
  }
}