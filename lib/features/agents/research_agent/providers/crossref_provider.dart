import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'paper_provider.dart';

class CrossrefProvider implements PaperProvider {
  static const String _baseUrl = "https://api.crossref.org/works";

  const CrossrefProvider();

  @override
  Future<Map<String, String>> lookup(String query) async {
    if (query.trim().isEmpty) return {};

    final uri = Uri.parse(_baseUrl).replace(queryParameters: {
      "query.bibliographic": query,
      "rows": "1",
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

    print("Crossref Lookup");
    print(uri);
    print(response.statusCode);

    if (response.statusCode == 429) {
      throw const RateLimitException("Crossref rate limited.");
    }

    if (response.statusCode != 200) {
      throw ProviderException(
        "Crossref HTTP ${response.statusCode}",
      );
    }

    final json = jsonDecode(response.body);

    final items =
        (json["message"]?["items"] as List<dynamic>?) ?? [];

    if (items.isEmpty) return {};

    final paper = items.first as Map<String, dynamic>;

    final authors = ((paper["author"] as List?) ?? [])
        .map((e) {
          final given = e["given"] ?? "";
          final family = e["family"] ?? "";
          return "$given $family".trim();
        })
        .join(", ");

    final titleList = paper["title"] as List? ?? [];
    final title =
        titleList.isNotEmpty ? titleList.first.toString() : "";

    final abstract = paper["abstract"]?.toString() ?? "";

    final year =
        ((paper["published-print"] ??
                    paper["published-online"])
                ?["date-parts"]?[0]?[0])
            ?.toString() ??
            "";

    final doi = paper["DOI"]?.toString() ?? "";

    return {
      "title": title,
      "authors": authors,
      "abstract": abstract,
      "year": year,
      "url": doi.isNotEmpty
          ? "https://doi.org/$doi"
          : "",
    };
  }

  @override
  Future<List<Map<String, String>>> search(
    String query, {
    int maxResults = 10,
  }) async {
    if (query.trim().isEmpty) return [];

    final uri = Uri.parse(_baseUrl).replace(queryParameters: {
      "query": query,
      "rows": "$maxResults",
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

    print("Crossref Search");
    print(uri);
    print(response.statusCode);

    if (response.statusCode == 429) {
      throw const RateLimitException("Crossref rate limited.");
    }

    if (response.statusCode != 200) {
      throw ProviderException(
        "Crossref HTTP ${response.statusCode}",
      );
    }

    final json = jsonDecode(response.body);

    final items =
        (json["message"]?["items"] as List<dynamic>?) ?? [];

    return items.map<Map<String, String>>((item) {
      final paper = item as Map<String, dynamic>;

      final titleList = paper["title"] as List? ?? [];

      final title =
          titleList.isNotEmpty ? titleList.first.toString() : "";

      final year =
          ((paper["published-print"] ??
                      paper["published-online"])
                  ?["date-parts"]?[0]?[0])
              ?.toString() ??
              "";

      final doi = paper["DOI"]?.toString() ?? "";

      return {
        "title": title,
        "snippet": "",
        "year": year,
        "url": doi.isNotEmpty
            ? "https://doi.org/$doi"
            : "",
      };
    }).toList();
  }
}