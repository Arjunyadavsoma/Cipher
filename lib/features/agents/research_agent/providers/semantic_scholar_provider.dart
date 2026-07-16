import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'paper_provider.dart';

class SemanticScholarProvider implements PaperProvider {
  static const String _baseUrl =
      "https://api.semanticscholar.org/graph/v1";

  @override
  Future<Map<String, String>> lookup(String query) async {
    if (query.trim().isEmpty) return {};

    final uri = Uri.parse(
      "$_baseUrl/paper/search",
    ).replace(queryParameters: {
      "query": query,
      "limit": "1",
      "fields": "title,authors,abstract,year,url",
    });

    final response = await http
        .get(
          uri,
          headers: const {
            "Accept": "application/json",
            "User-Agent": "MimirAI",
          },
        )
        .timeout(const Duration(seconds: 20));

    print("Semantic Scholar Lookup");
    print(uri);
    print(response.statusCode);

    if (response.statusCode == 429) {
      throw const RateLimitException(
        "Semantic Scholar rate limit reached.",
      );
    }

    if (response.statusCode != 200) {
      throw ProviderException(
        "Semantic Scholar HTTP ${response.statusCode}",
      );
    }

    final json = jsonDecode(response.body);

    final papers = json["data"] as List? ?? [];

    if (papers.isEmpty) return {};

    final paper = papers.first as Map<String, dynamic>;

    final authors = (paper["authors"] as List? ?? [])
        .map((e) => e["name"])
        .join(", ");

    return {
      "title": paper["title"] ?? "",
      "authors": authors,
      "abstract": paper["abstract"] ?? "",
      "year": paper["year"]?.toString() ?? "",
      "url": paper["url"] ?? "",
    };
  }

  @override
  Future<List<Map<String, String>>> search(
    String query, {
    int maxResults = 10,
  }) async {
    if (query.trim().isEmpty) return [];

    final uri = Uri.parse(
      "$_baseUrl/paper/search",
    ).replace(queryParameters: {
      "query": query,
      "limit": maxResults.toString(),
      "fields": "title,abstract,year,url",
    });

    final response = await http
        .get(
          uri,
          headers: const {
            "Accept": "application/json",
            "User-Agent": "MimirAI",
          },
        )
        .timeout(const Duration(seconds: 20));

    print("Semantic Scholar Search");
    print(uri);
    print(response.statusCode);

    if (response.statusCode == 429) {
      throw const RateLimitException(
        "Semantic Scholar rate limit reached.",
      );
    }

    if (response.statusCode != 200) {
      throw ProviderException(
        "Semantic Scholar HTTP ${response.statusCode}",
      );
    }

    final json = jsonDecode(response.body);

    final papers = json["data"] as List? ?? [];

    return papers.map<Map<String, String>>((item) {
      final paper = item as Map<String, dynamic>;

      final abstract = paper["abstract"] ?? "";

      return {
        "title": paper["title"] ?? "",
        "snippet": abstract.length > 220
            ? "${abstract.substring(0, 220)}..."
            : abstract,
        "year": paper["year"]?.toString() ?? "",
        "url": paper["url"] ?? "",
      };
    }).toList();
  }
}