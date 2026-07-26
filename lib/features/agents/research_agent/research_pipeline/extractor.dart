import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../core/tool_manager.dart';

class InformationExtractor {
  final _toolManager = ToolManager.instance;

  /// Extracts structured information from a list of search snippets.
  Future<List<Map<String, dynamic>>> extract(List<Map<String, String>> searchResults, String originalQuery) async {
    final buffer = StringBuffer();
    buffer.writeln("Original Query: $originalQuery\n");
    buffer.writeln("Search Results Snippets:");
    for (int i = 0; i < searchResults.length; i++) {
      buffer.writeln("Result ${i + 1}: ${searchResults[i]['title']} - ${searchResults[i]['snippet']}");
    }


    try {
      final response = await _toolManager.executeTool('groq', {
        'systemPrompt': 'You are an information extraction engine. Output ONLY a JSON array. No markdown.',
        'message': buffer.toString(),
        'temperature': 0.0,
      }) as String;

      final cleaned = _extractJson(response);
      final List<dynamic> list = jsonDecode(cleaned);
      return list.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('InformationExtractor failed: $e');
      return [];
    }
  }

  String _extractJson(String text) {
    final start = text.indexOf('[');
    final end = text.lastIndexOf(']');
    if (start == -1 || end == -1) return '[]';
    return text.substring(start, end + 1);
  }
}