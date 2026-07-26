import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'html_cleaner.dart';

class ContentFetcher {
  /// Fetches a URL and extracts the main article text.
  Future<String> fetchAndClean(String url) async {
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        // Use our HTML cleaner to strip scripts, menus, and tags
        return HtmlCleaner.extractMainContent(response.body);
      }
    } catch (e) {
      debugPrint('ContentFetcher failed for $url: $e');
    }
    return '';
  }
}