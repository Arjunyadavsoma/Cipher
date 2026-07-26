import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class CommunitySearchTool {
  Future<List<Map<String, String>>> searchAll(String query) async {
    final results = await Future.wait([
      _searchGitHub(query),
      _searchReddit(query),
      _searchHackerNews(query),
    ]);
    return results.expand((list) => list).toList();
  }

  Future<List<Map<String, String>>> _searchGitHub(String query) async {
    try {
      // Increased per_page to 10
      final res = await http.get(Uri.parse('https://api.github.com/search/repositories?q=$query&sort=stars&per_page=10'));
      if (res.statusCode == 200) {
        final items = (jsonDecode(res.body)['items'] as List?) ?? [];
        return items.map<Map<String, String>>((r) {
          final map = r as Map<String, dynamic>;
          return {
            'title': '${map['full_name'] ?? ''} ⭐ ${map['stargazers_count'] ?? 0}',
            'url': (map['html_url'] ?? '').toString(),
            'snippet': (map['description'] ?? '').toString(),
          };
        }).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<List<Map<String, String>>> _searchReddit(String query) async {
    try {
      // Increased limit to 10
      final res = await http.get(Uri.parse('https://www.reddit.com/search.json?q=$query&limit=10&sort=relevance'));
      if (res.statusCode == 200) {
        final children = (jsonDecode(res.body)['data']['children'] as List?) ?? [];
        return children.map<Map<String, String>>((c) {
          final d = c['data'] as Map<String, dynamic>;
          return {
            'title': 'Reddit: ${d['title'] ?? ''}',
            'url': 'https://reddit.com${d['permalink'] ?? ''}',
            'snippet': (d['selftext'] ?? '').toString(),
          };
        }).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<List<Map<String, String>>> _searchHackerNews(String query) async {
    try {
      // Increased hitsPerPage to 10
      final res = await http.get(Uri.parse('http://hn.algolia.com/api/v1/search?query=$query&tags=story&hitsPerPage=10'));
      if (res.statusCode == 200) {
        final hits = (jsonDecode(res.body)['hits'] as List?) ?? [];
        return hits.map<Map<String, String>>((h) {
          final map = h as Map<String, dynamic>;
          return {
            'title': 'HN: ${map['title'] ?? 'Unknown'}',
            'url': (map['url'] ?? 'https://news.ycombinator.com/item?id=${map['objectID']}').toString(),
            'snippet': '',
          };
        }).toList();
      }
    } catch (_) {}
    return [];
  }
}