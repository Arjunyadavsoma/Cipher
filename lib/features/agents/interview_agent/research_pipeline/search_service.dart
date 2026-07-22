import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class SearchResult {
  final String title;
  final String url;
  final String content;

  SearchResult({required this.title, required this.url, required this.content});
}

class SearchService {
  // Read from .env like your ApiKeyPoolService does
  final String apiKey = dotenv.env['TAVILY_API_KEY'] ?? '';
  final String apiUrl = 'https://api.tavily.com/search';

  Future<List<SearchResult>> search(String query) async {
    if (apiKey.isEmpty) {
      print("Tavily API Key missing from .env");
      return [];
    }
    
    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'api_key': apiKey,
          'query': query,
          'max_results': 10,
        }),
      );
      // ... rest of the code remains exactly the same ...
      if (response.statusCode != 200) {
        print('Search API failed: ${response.statusCode}');
        return [];
      }

      final data = jsonDecode(response.body);
      List<dynamic> results = data['results'] ?? [];

      return results.map((r) {
        return SearchResult(
          title: r['title'] ?? '',
          url: r['url'] ?? '',
          content: r['content'] ?? '',
        );
      }).toList();
    } catch (e) {
      print('SearchService Error: $e');
      return [];
    }
  }
}