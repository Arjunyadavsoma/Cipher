import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class TavilySearchTool {
  // TODO: Replace with your Tavily API Key (https://tavily.com)
  final String _apiKey = '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';
  static const String _url = 'https://api.tavily.com/search';

  Future<List<Map<String, String>>> search(String query, {int maxResults = 10}) async {
    try {
      final response = await http.post(
        Uri.parse(_url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'api_key': _apiKey,
          'query': query,
          'search_depth': 'advanced', // Use 'advanced' for deep research
          'max_results': maxResults,
          'include_answer': 'true',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data['results'] as List? ?? [];
        
        return results.map<Map<String, String>>((item) {
          return {
            'title': item['title'] ?? '',
            'url': item['url'] ?? '',
            'snippet': item['content'] ?? '', // Tavily provides clean extracted content
          };
        }).toList();
      } else {
        debugPrint('Tavily Error: ${response.body}');
        return [];
      }
    } catch (e) {
      debugPrint('TavilySearchTool failed: $e');
      return [];
    }
  }
}