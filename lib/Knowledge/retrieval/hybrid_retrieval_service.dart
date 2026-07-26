import 'package:flutter/foundation.dart';
import 'package:cipher_ai/Knowledge/knowledge_entry.dart';
import 'package:cipher_ai/Knowledge/knowledge_repository.dart';
import 'package:cipher_ai/Knowledge/nvidia_embedding_service.dart';

import 'scoring_engine.dart';
import 'query_expander.dart';
import 'context_compressor.dart';

class HybridRetrievalService {
  final _repo = KnowledgeRepository.instance;
  final _embedder = NvidiaEmbeddingService.instance;
  final _scoringEngine = ScoringEngine();
  
  // NEW: Initialize the Phase 7 & 3 components
  final _queryExpander = QueryExpander();
  final _contextCompressor = ContextCompressor();

  Future<String> buildDomainContext({
    required String userId,
    required String userQuery,
    required List<String> queryTags,
  }) async {
    try {
      // 1. QUERY EXPANSION (Phase 7)
      final expandedQueries = await _queryExpander.expandQuery(userQuery);
      debugPrint("Expanded Queries: $expandedQueries");

      // 2. PARALLEL EMBEDDING & FETCHING
      // Embed all expanded queries simultaneously
      final vectorFutures = expandedQueries.map((q) => _embedder.embed(q, isQuery: true)).toList();
      final queryVectors = await Future.wait(vectorFutures);

      // Fetch candidates for all vectors, plus tags and recency
      final searchFutures = <Future<List<KnowledgeEntry>>>[];
      
      for (final vector in queryVectors) {
        searchFutures.add(_repo.vectorSearch(userId: userId, queryVector: vector, limit: 20));
      }
      
      searchFutures.add(_repo.queryAllLayers(userId: userId, tags: queryTags, limitPerLayer: 5));
      // FIX: Changed to positional argument for userId
      searchFutures.add(_repo.getRecentFacts(userId, limit: 5));

      final results = await Future.wait(searchFutures);

      // 3. MERGE & DEDUPLICATE CANDIDATES
      final uniqueCandidates = <String, KnowledgeEntry>{};
      // We also track which candidates were hit by vector search for semantic scoring
      final vectorHitIds = <String>{};

      for (final list in results) {
        for (final e in list) {
          uniqueCandidates[e.id] = e;
        }
      }
      
      // Mark vector hits (assuming first N results lists are from vectorSearch)
      int vectorListCount = queryVectors.length;
      for (int i = 0; i < vectorListCount; i++) {
        for (final e in results[i]) {
          vectorHitIds.add(e.id);
        }
      }

      if (uniqueCandidates.isEmpty) return '';

      // 4. SCORE CANDIDATES
      final queryLower = userQuery.toLowerCase();
      final scoredEntries = <MapEntry<KnowledgeEntry, double>>[];

      for (final entry in uniqueCandidates.values) {
        final keywordMatch = entry.fact.toLowerCase().contains(queryLower);
        final tagMatchCount = entry.tags.where((t) => queryTags.contains(t)).length;
        
        // If it was hit by any of the expanded query vectors, give it high semantic score
        final semanticScore = vectorHitIds.contains(entry.id) ? 0.9 : 0.1;

        final score = _scoringEngine.calculateScore(
          entry: entry,
          semanticScore: semanticScore,
          keywordMatch: keywordMatch,
          tagMatchCount: tagMatchCount,
          query: userQuery,
        );

        scoredEntries.add(MapEntry(entry, score));
      }

      // 5. SORT BY SCORE & TAKE TOP 5
      scoredEntries.sort((a, b) => b.value.compareTo(a.value));
      final selected = scoredEntries.take(5).map((e) => e.key).toList();

      // 6. UPDATE ACCESS COUNT (Fire and forget)
      for (final entry in selected) {
        _repo.touchLastUsed(userId, entry).catchError((_) {});
      }

      // 7. CONTEXT COMPRESSION (Phase 3)
      // Compress and deduplicate the final 5 facts before returning
      return _contextCompressor.compress(selected);

    } catch (e) {
      debugPrint('HybridRetrievalService failed: $e');
      return '';
    }
  }
}