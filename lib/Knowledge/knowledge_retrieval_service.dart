import 'knowledge_entry.dart';
import 'knowledge_repository.dart';

/// Turns QueryPlan.requiredKnowledgeTags into a compact context string
/// ready to drop into ExecutionContext.domainContext. Tag-match based
/// (not embeddings) - a deliberate choice given knowledge entries are
/// already short, atomic, tagged facts rather than long documents, so
/// exact/overlapping tag matching is cheap and precise enough without
/// standing up vector search.
class KnowledgeRetrievalService {
  KnowledgeRetrievalService._internal();

  static final KnowledgeRetrievalService instance =
      KnowledgeRetrievalService._internal();

  final _repo = KnowledgeRepository.instance;

  /// Hard cap on total facts injected regardless of how many layers
  /// matched - keeps prompt token cost bounded and predictable, same
  /// reasoning as ContextSummarizerService capping memory at 15 entries.
  static const _maxTotalFacts = 12;

  Future<String> buildDomainContext({
    required String userId,
    required List<String> tags,
  }) async {
    if (tags.isEmpty) return '';

    List<KnowledgeEntry> matched;
    try {
      matched = await _repo.queryAllLayers(userId: userId, tags: tags);
    } catch (_) {
      // Retrieval failing shouldn't block the agent from running - it
      // just runs without extra context, same as RssController treating
      // a saved-source load failure as non-fatal.
      return '';
    }

    if (matched.isEmpty) return '';

    matched.sort((a, b) => b.importance.compareTo(a.importance));
    final selected = matched.take(_maxTotalFacts).toList();

    // Fire-and-forget - don't block the response on updating
    // lastUsedAt for each matched entry.
    for (final entry in selected) {
      // ignore: unawaited_futures
      _repo.touchLastUsed(userId, entry);
    }

    final byLayer = <String, List<KnowledgeEntry>>{};
    for (final entry in selected) {
      byLayer.putIfAbsent(entry.layer, () => []).add(entry);
    }

    final buffer = StringBuffer('Relevant knowledge about the user:');
    for (final layer in byLayer.keys) {
      buffer.writeln();
      buffer.writeln('$layer:');
      for (final entry in byLayer[layer]!) {
        buffer.writeln('- ${entry.fact}');
      }
    }

    return buffer.toString().trim();
  }
}
