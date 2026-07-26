import 'dart:async';
import 'package:flutter/foundation.dart';
import '../web_tools/tavily_search.dart';
import '../web_tools/community_search.dart';
import '../web_tools/youtube_search.dart';
import '../web_tools/stackoverflow_search.dart';
import '../web_tools/wikipedia_search.dart';

class SearchManager {
  final _tavily = TavilySearchTool();
  final _community = CommunitySearchTool();
  final _youtube = YouTubeSearchTool();
  final _stackOverflow = StackOverflowSearchTool();
  final _wikipedia = WikipediaSearchTool();

  Future<List<Map<String, String>>> searchAll(String query) async {
    final futures = <Future<List<Map<String, String>>>>[
      _safeSearch(() => _tavily.search(query, maxResults: 10)), // Increased to 10
      _safeSearch(() => _community.searchAll(query)),
      _safeSearch(() => _youtube.search(query, maxResults: 5)), // Increased to 5
      _safeSearch(() => _stackOverflow.search(query, maxResults: 5)), // Increased to 5
      _safeSearch(() => _wikipedia.search(query, maxResults: 3)), // Increased to 3
    ];

    final results = await Future.wait(futures);
    final flatResults = results.expand((list) => list).toList();

    // Deduplicate by URL
    final seenUrls = <String>{};
    return flatResults.where((r) {
      final url = r['url'] ?? '';
      if (url.isEmpty || seenUrls.contains(url)) return false;
      seenUrls.add(url);
      return true;
    }).toList();
  }

  Future<List<Map<String, String>>> _safeSearch(Future<List<Map<String, String>>> Function() task) async {
    try { return await task(); } catch (e) { debugPrint('Search failed: $e'); return []; }
  }
}