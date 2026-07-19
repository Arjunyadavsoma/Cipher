import 'knowledge_entry.dart';
import 'knowledge_repository.dart';

class KnowledgeRetrievalService {
  KnowledgeRetrievalService._internal();
  static final KnowledgeRetrievalService instance =
      KnowledgeRetrievalService._internal();

  final _repo = KnowledgeRepository.instance;

  static const _maxTotalFacts = 15;
  static const _maxContextChars = 1200; // ~300 tokens, keeps prompt cost low

  Future<String> buildDomainContext({
    required String userId,
    required List<String> tags,
  }) async {
    // ┌─────────────────────────────────────────────────────────┐
    // │ FIX: Use 'late' so Dart knows it will be assigned in   │
    // │ the try block below.                                    │
    // └─────────────────────────────────────────────────────────┘
    late List<KnowledgeEntry> matched;

    try {
      if (tags.isEmpty) {
        // Fallback: If no tags, pull the 5 most recently used facts
        // ignore: avoid_print
        print('⚠️ No tags provided. Falling back to recent facts.');
        matched = await _repo.getRecentFacts(userId, limit: 5);
      } else {
        matched = await _repo.queryAllLayers(userId: userId, tags: tags);
      }
    } catch (e) {
      // ignore: avoid_print
      print('KnowledgeRetrievalService.buildDomainContext failed: $e');
      return '';
    }

    if (matched.isEmpty) return '';

    // Sort by importance
    matched.sort((a, b) => b.importance.compareTo(a.importance));

    final selected = <KnowledgeEntry>[];
    int currentChars = 0;

    // Iterate and add facts until we hit the character or count limit
    for (final entry in matched) {
      if (selected.length >= _maxTotalFacts) break;

      final entryLength = entry.fact.length + 10; // +10 for formatting
      if (currentChars + entryLength > _maxContextChars) break;

      selected.add(entry);
      currentChars += entryLength;

      // Fire-and-forget lastUsedAt update
      // ignore: unawaited_futures
      _repo.touchLastUsed(userId, entry).catchError((e) {
        // ignore: avoid_print
        print(
          'KnowledgeRetrievalService: touchLastUsed failed for '
          '${entry.id}: $e',
        );
      });
    }

    final byLayer = <String, List<KnowledgeEntry>>{};
    for (final entry in selected) {
      byLayer.putIfAbsent(entry.layer, () => []).add(entry);
    }

    // ┌─────────────────────────────────────────────────────────┐
    // │ FIX: Instruct the AI to ONLY use facts relevant to the  │
    // │ specific question, rather than reciting everything.     │
    // └─────────────────────────────────────────────────────────┘
    final buffer = StringBuffer(
      'Background knowledge (Only use the specific facts from this list that are necessary to answer the user\'s current question. Do not mention unrelated facts):',
    );
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