import 'package:cipher_ai/features/agents/research_agent/providers/arxiv_provider.dart';
import 'package:cipher_ai/features/agents/research_agent/providers/crossref_provider.dart';
import 'package:cipher_ai/features/agents/research_agent/providers/paper_provider.dart';
import 'package:cipher_ai/features/agents/research_agent/providers/semantic_scholar_provider.dart';

import '../models/tool.dart';

class ResearchApiException implements Exception {
  final String message;

  const ResearchApiException(this.message);

  @override
  String toString() => message;
}

class ResearchTool implements Tool {
  @override
  String get name => "research";

  final PaperProvider _semantic = SemanticScholarProvider();
  final PaperProvider _crossref = CrossrefProvider();
  final PaperProvider _arxiv = ArxivProvider();

  @override
  Future<dynamic> execute(Map<String, dynamic> input) async {
    final type = input["type"] as String? ?? "";

    switch (type) {
      case "lookup":
        return lookup(input["query"] as String? ?? "");

      case "search":
        return search(
          input["query"] as String? ?? "",
          maxResults: input["maxResults"] as int? ?? 10,
        );

      default:
        throw const ResearchApiException("Unknown research request.");
    }
  }

  Future<Map<String, String>> lookup(String query) async {
    if (query.trim().isEmpty) {
      return {};
    }

    final providers = <PaperProvider>[_semantic, _crossref, _arxiv];

    for (final provider in providers) {
      try {
        final result = await provider.lookup(query);

        if (result.isNotEmpty) {
          return result;
        }
      } on RateLimitException catch (e) {
        print(e);
        continue;
      } on ProviderException catch (e) {
        print(e);
        continue;
      } catch (e) {
        print(e);
        continue;
      }
    }

    return {};
  }

  Future<List<Map<String, String>>> search(
    String query, {
    int maxResults = 10,
  }) async {
    if (query.trim().isEmpty) {
      return [];
    }

    final providers = <PaperProvider>[_semantic, _crossref, _arxiv];

    for (final provider in providers) {
      try {
        final result = await provider.search(query, maxResults: maxResults);

        if (result.isNotEmpty) {
          return result;
        }
      } on RateLimitException catch (e) {
        print(e);
        continue;
      } on ProviderException catch (e) {
        print(e);
        continue;
      } catch (e) {
        print(e);
        continue;
      }
    }

    return [];
  }
}
