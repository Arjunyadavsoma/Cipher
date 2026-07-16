import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import 'paper_provider.dart';

class ArxivProvider implements PaperProvider {
  static const String _baseUrl =
      "http://export.arxiv.org/api/query";

  const ArxivProvider();

  @override
  Future<Map<String, String>> lookup(String query) async {
    if (query.trim().isEmpty) return {};

    final uri = Uri.parse(_baseUrl).replace(queryParameters: {
      "search_query": "all:$query",
      "start": "0",
      "max_results": "1",
    });

    final response = await http
        .get(
          uri,
          headers: const {
            "User-Agent": "MimirAI",
          },
        )
        .timeout(const Duration(seconds: 20));

    print("arXiv Lookup");
    print(uri);
    print(response.statusCode);

    if (response.statusCode == 429) {
      throw const RateLimitException("arXiv rate limited.");
    }

    if (response.statusCode != 200) {
      throw ProviderException(
        "arXiv HTTP ${response.statusCode}",
      );
    }

    final xml = XmlDocument.parse(response.body);

    final entries = xml.findAllElements("entry");

    if (entries.isEmpty) {
      return {};
    }

    final entry = entries.first;

    final authors = entry
        .findElements("author")
        .map(
          (e) => e.findElements("name").first.innerText,
        )
        .join(", ");

    return {
      "title": _text(entry, "title"),
      "authors": authors,
      "abstract": _text(entry, "summary"),
      "year": _year(entry),
      "url": _text(entry, "id"),
    };
  }

  @override
  Future<List<Map<String, String>>> search(
    String query, {
    int maxResults = 10,
  }) async {
    if (query.trim().isEmpty) return [];

    final uri = Uri.parse(_baseUrl).replace(queryParameters: {
      "search_query": "all:$query",
      "start": "0",
      "max_results": "$maxResults",
    });

    final response = await http
        .get(
          uri,
          headers: const {
            "User-Agent": "MimirAI",
          },
        )
        .timeout(const Duration(seconds: 20));

    print("arXiv Search");
    print(uri);
    print(response.statusCode);

    if (response.statusCode == 429) {
      throw const RateLimitException("arXiv rate limited.");
    }

    if (response.statusCode != 200) {
      throw ProviderException(
        "arXiv HTTP ${response.statusCode}",
      );
    }

    final xml = XmlDocument.parse(response.body);

    final entries = xml.findAllElements("entry");

    return entries.map<Map<String, String>>((entry) {
      final summary = _text(entry, "summary");

      return {
        "title": _text(entry, "title"),
        "snippet": summary.length > 220
            ? "${summary.substring(0, 220)}..."
            : summary,
        "year": _year(entry),
        "url": _text(entry, "id"),
      };
    }).toList();
  }

  String _text(XmlElement element, String tag) {
    final node = element.findElements(tag);

    if (node.isEmpty) {
      return "";
    }

    return node.first.innerText.trim();
  }

  String _year(XmlElement entry) {
    final published = _text(entry, "published");

    if (published.length >= 4) {
      return published.substring(0, 4);
    }

    return "";
  }
}