import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;

class CrawlManager {
  /// Fetches URLs in parallel, cleans HTML, and chunks the text.
  Future<List<Map<String, String>>> fetchAndChunk(List<Map<String, String>> urls) async {
    final fetchFutures = urls.map((u) => _fetchAndClean(u['url'] ?? ''));
    final cleanedTexts = await Future.wait(fetchFutures);

    final chunks = <Map<String, String>>[];
    for (int i = 0; i < urls.length; i++) {
      if (cleanedTexts[i].isEmpty) continue;

            // Simple chunking: split by double newlines, group into ~4000 char blocks
      final paragraphs = cleanedTexts[i].split(RegExp(r'\n{2,}'));
      final buffer = StringBuffer();
      for (final p in paragraphs) {
        if (buffer.length + p.length > 4000) { // Increased from 3000 to 4000
          chunks.add({
            'title': urls[i]['title'] ?? '',
            'url': urls[i]['url'] ?? '',
            'text': buffer.toString(),
          });
          buffer.clear();
        }
        buffer.writeln(p);
      }
      if (buffer.isNotEmpty) {
        chunks.add({
          'title': urls[i]['title'] ?? '',
          'url': urls[i]['url'] ?? '',
          'text': buffer.toString(),
        });
      }
    }
    return chunks;
  }

  Future<String> _fetchAndClean(String url) async {
    try {
      final res = await http.get(Uri.parse(url), headers: {'User-Agent': 'Mozilla/5.0'}).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return '';
      
      final document = html_parser.parse(res.body);
      for (final selector in ['script', 'style', 'header', 'footer', 'nav', 'aside', 'form', 'iframe']) {
        document.querySelectorAll(selector).forEach((el) => el.remove());
      }
      return (document.querySelector('article') ?? document.body)?.text.trim() ?? '';
    } catch (e) {
      debugPrint('Crawl failed for $url: $e');
      return '';
    }
  }
}