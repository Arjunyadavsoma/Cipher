import 'dart:convert';
import 'package:http/http.dart' as http;

class WikipediaSearchTool {
  Future<List<Map<String, String>>> search(String query, {int maxResults = 2}) async {
    try {
      // 1. Search for the page title
      final searchRes = await http.get(
        Uri.parse('https://en.wikipedia.org/w/api.php?action=query&list=search&srsearch=${Uri.encodeComponent(query)}&format=json&srlimit=$maxResults'),
      ).timeout(const Duration(seconds: 10));

      if (searchRes.statusCode == 200) {
        final searchItems = (jsonDecode(searchRes.body)['query']?['search'] as List?) ?? [];
        final results = <Map<String, String>>[];

        // 2. Fetch the extract (first paragraph) for each page
        for (final item in searchItems) {
          final title = item['title'] as String;
          final extractRes = await http.get(
            Uri.parse('https://en.wikipedia.org/w/api.php?action=query&prop=extracts&exintro&explaintext&titles=${Uri.encodeComponent(title)}&format=json'),
          );
          
          if (extractRes.statusCode == 200) {
            final pages = (jsonDecode(extractRes.body)['query']?['pages'] as Map?) ?? {};
            final page = pages.values.first;
            final extract = page['extract'] as String? ?? '';
            
            results.add({
              'title': 'Wikipedia: $title',
              'url': 'https://en.wikipedia.org/wiki/${Uri.encodeComponent(title)}',
              'snippet': extract.length > 500 ? '${extract.substring(0, 500)}...' : extract,
            });
          }
        }
        return results;
      }
    } catch (_) {}
    return [];
  }
}