import 'dart:convert';
import 'package:http/http.dart' as http;

class StackOverflowSearchTool {
  Future<List<Map<String, String>>> search(String query, {int maxResults = 3}) async {
    try {
      final res = await http.get(
        Uri.parse('https://api.stackexchange.com/2.3/search/advanced?order=desc&sort=relevance&q=${Uri.encodeComponent(query)}&site=stackoverflow&pagesize=$maxResults'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final items = (jsonDecode(res.body)['items'] as List?) ?? [];
        return items.map<Map<String, String>>((item) {
          return {
            'title': 'StackOverflow: ${item['title'] ?? ''}',
            'url': item['link'] ?? '',
            'snippet': 'Score: ${item['score'] ?? 0}. ${item['is_answered'] == true ? "Answered." : "No accepted answer yet."}',
          };
        }).toList();
      }
    } catch (_) {}
    return [];
  }
}