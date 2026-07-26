import 'package:flutter/foundation.dart';
import 'knowledge_entry.dart';
import 'knowledge_repository.dart';
import 'nvidia_embedding_service.dart';

class KnowledgeRetrievalService {
  KnowledgeRetrievalService._internal();
  static final KnowledgeRetrievalService instance =
      KnowledgeRetrievalService._internal();

  final _repo = KnowledgeRepository.instance;
  final _embedder = NvidiaEmbeddingService.instance;

  static const _maxTotalFacts = 5; 
  static const _maxContextChars = 1200;

  Future<String> buildDomainContext({
    required String userId,
    required String userQuery,
  }) async {
    late List<KnowledgeEntry> matched;

    try {
      if (userQuery.trim().isEmpty) {
        matched = await _repo.getRecentFacts(userId, limit: 3);
      } else {
        // 1. Embed the user's query
        final queryVector = await _embedder.embed(userQuery, isQuery: true);
        
        // 2. Perform Vector Search
        matched = await _repo.vectorSearch(
          userId: userId, 
          queryVector: queryVector,
          limit: 10,
        );
      }
    } catch (e) {
      debugPrint('❌ KnowledgeRetrievalService.buildDomainContext failed: $e');
      return '';
    }

    if (matched.isEmpty) return '';

    // Sort by importance as a secondary ranking signal
    matched.sort((a, b) => b.importance.compareTo(a.importance));

    final selected = <KnowledgeEntry>[];
    int currentChars = 0;

    for (final entry in matched) {
      if (selected.length >= _maxTotalFacts) break;

      final entryLength = entry.fact.length + 10;
      if (currentChars + entryLength > _maxContextChars) break;

      selected.add(entry);
      currentChars += entryLength;

      _repo.touchLastUsed(userId, entry).catchError((_) {});
    }

    final buffer = StringBuffer(
      'Background knowledge (Only use the specific facts from this list that are necessary to answer the user\'s current question. Do not mention unrelated facts):',
    );
    
    for (final entry in selected) {
      buffer.writeln();
      buffer.writeln('- ${entry.fact} [Layer: ${entry.layer}]');
    }

    return buffer.toString().trim();
  }
}