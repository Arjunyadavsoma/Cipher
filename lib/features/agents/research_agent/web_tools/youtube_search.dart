
import 'package:http/http.dart' as http;

class YouTubeSearchTool {
  // Uses YouTube's public JSON endpoint (no API key required for basic search)
  Future<List<Map<String, String>>> search(String query, {int maxResults = 3}) async {
    try {
      final res = await http.get(
        Uri.parse('https://www.youtube.com/results?search_query=${Uri.encodeComponent(query)}'),
        headers: {'User-Agent': 'Mozilla/5.0'},
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) return [];

      // Parse the raw HTML to extract video IDs and titles
      final html = res.body;
      final regex = RegExp(r'"videoRenderer":{"videoId":"([\w-]+)".*?"title":{"runs":\[\{"text":"([^"]+)"');
      final matches = regex.allMatches(html);

      final results = <Map<String, String>>[];
      int count = 0;
      for (final match in matches) {
        if (count >= maxResults) break;
        final videoId = match.group(1) ?? '';
        final title = match.group(2) ?? '';
        if (videoId.isNotEmpty) {
          results.add({
            'title': 'YouTube: $title',
            'url': 'https://www.youtube.com/watch?v=$videoId',
            'snippet': 'Video content. (Transcript extraction requires a dedicated API or external service).',
          });
          count++;
        }
      }
      return results;
    } catch (_) {
      return [];
    }
  }
}