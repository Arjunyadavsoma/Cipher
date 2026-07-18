import 'dart:convert';
import 'package:mimir_ai/features/agents/DSA_agent/dsa_question.dart';
import 'package:mimir_ai/features/agents/core/tool_manager.dart';

class GfgFetchService {
  final _toolManager = ToolManager.instance;

  Future<DsaQuestion> fetchProblemOfTheDay() async {
    try {
      final rawHtml = await _toolManager.executeTool('http', {
        'url': 'https://practice.geeksforgeeks.org/problem-of-the-day',
      }) as String;

      // Anti-Hallucination / Cloudflare Check
      if (rawHtml.isEmpty || rawHtml.contains("Just a moment...") || rawHtml.contains("cf-browser-verification")) {
        throw Exception("GeeksforGeeks is blocking the request (Cloudflare).");
      }

      final extractionPrompt = "Extract the Problem of the Day from this GeeksforGeeks HTML. "
          "Return ONLY a valid JSON object with keys: 'title', 'difficulty', 'description', 'url'. "
          "Make sure the 'url' is the full link to the problem. The 'description' should include the problem statement and examples if visible. \n\nHTML:\n$rawHtml";

      final llmResponse = await _toolManager.executeTool('groq', {
        'systemPrompt': 'You are an HTML parser. You only output valid JSON. No markdown, no explanation.',
        'message': extractionPrompt,
        'history': const [],
        'temperature': 0.0,
      });

      final cleaned = _extractJson(llmResponse as String);
      final data = jsonDecode(cleaned) as Map<String, dynamic>;

      return DsaQuestion(
        id: DateTime.now().toUtc().toIso8601String().split('T')[0],
        title: data['title'] ?? 'Unknown POTD',
        description: data['description'] ?? 'No description available.',
        difficulty: data['difficulty'] ?? 'Medium',
        tags: ['GFG', 'POTD'],
        url: data['url'] ?? 'https://practice.geeksforgeeks.org/problem-of-the-day',
      );
    } catch (e) {
      throw Exception("Failed to fetch/parse GFG Problem: $e");
    }
  }

  String _extractJson(String text) {
    var cleaned = text.trim();
    if (cleaned.startsWith('```')) {
      cleaned = cleaned
          .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
          .replaceFirst(RegExp(r'\s*```$'), '');
    }
    final start = cleaned.indexOf('{');
    final end = cleaned.lastIndexOf('}');
    if (start == -1 || end == -1) return '{}';
    return cleaned.substring(start, end + 1);
  }
}