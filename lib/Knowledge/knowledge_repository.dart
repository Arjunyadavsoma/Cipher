import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;

import 'knowledge_entry.dart';

/// Firestore access for layered knowledge:
///   users/{uid}/knowledge/{layer}/entries/{entryId}
///
/// Mirrors AgentMemoryRepository's convention of being the one seam that
/// touches this collection - callers (KnowledgeRetrievalService,
/// KnowledgeWriteService) never build Firestore paths themselves.
class KnowledgeRepository {
  KnowledgeRepository._internal();

  static final KnowledgeRepository instance = KnowledgeRepository._internal();

  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _entriesRef(
    String userId,
    String layer,
  ) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('knowledge')
        .doc(layer)
        .collection('entries');
  }

  Future<KnowledgeEntry> addEntry({
    required String userId,
    required KnowledgeEntry entry,
  }) async {
    final doc = await _entriesRef(userId, entry.layer).add(entry.toMap());
    return entry.copyWith();
  }

  /// Queries a single layer for entries matching any of [tags], ranked
  /// by importance, capped at [limit]. Firestore's arrayContainsAny
  /// caps at 10 values, so callers should keep tag lists tight.
  ///
  /// Combining `arrayContainsAny` with `orderBy` on a different field
  /// (importance) requires a Firestore composite index. Until that
  /// index is created in the Firebase console, this query throws
  /// `failed-precondition` on every call - caught below so one missing
  /// index doesn't silently zero out retrieval, and logged so it's
  /// actually visible instead of vanishing into KnowledgeRetrievalService's
  /// catch-all.
  Future<List<KnowledgeEntry>> queryLayer({
    required String userId,
    required String layer,
    required List<String> tags,
    int limit = 5,
  }) async {
    if (tags.isEmpty) return [];

    final tagsToMatch = tags.take(10).toList();

    try {
      final snapshot = await _entriesRef(userId, layer)
          .where('tags', arrayContainsAny: tagsToMatch)
          .orderBy('importance', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs
          .map((d) => KnowledgeEntry.fromMap(d.id, d.data()))
          .toList();
    } on FirebaseException catch (e) {
      if (e.code == 'failed-precondition') {
        // ignore: avoid_print
        print(
          'KnowledgeRepository.queryLayer: no composite index yet for '
          'layer "$layer" (tags arrayContainsAny + importance orderBy) - '
          'falling back to an unordered fetch. Create the index Firestore '
          'suggests in the error below to get true top-by-importance '
          'ranking instead of this approximation:\n$e',
        );
        return _queryLayerWithoutIndex(userId, layer, tagsToMatch, limit);
      }
      // ignore: avoid_print
      print('KnowledgeRepository.queryLayer: layer "$layer" failed: $e');
      return [];
    } catch (e) {
      // ignore: avoid_print
      print('KnowledgeRepository.queryLayer: layer "$layer" failed: $e');
      return [];
    }
  }

  /// Fallback used when the composite index above doesn't exist yet.
  /// Fetches by tag match alone (no server-side order), then sorts by
  /// importance client-side. Only approximates "top N by importance"
  /// when a layer has more matches than [limit] - the real fix is
  /// still creating the composite index.
  Future<List<KnowledgeEntry>> _queryLayerWithoutIndex(
    String userId,
    String layer,
    List<String> tags,
    int limit,
  ) async {
    final snapshot = await _entriesRef(
      userId,
      layer,
    ).where('tags', arrayContainsAny: tags).get();

    final entries = snapshot.docs
        .map((d) => KnowledgeEntry.fromMap(d.id, d.data()))
        .toList()
      ..sort((a, b) => b.importance.compareTo(a.importance));

    return entries.take(limit).toList();
  }

  /// Queries every layer for [tags] in one pass. Runs layer queries
  /// concurrently rather than sequentially - six small queries in
  /// parallel is far cheaper latency-wise than six in series.
  Future<List<KnowledgeEntry>> queryAllLayers({
    required String userId,
    required List<String> tags,
    int limitPerLayer = 5,
  }) async {
    if (tags.isEmpty) return [];

    final results = await Future.wait(
      KnowledgeLayers.all.map(
        (layer) => queryLayer(
          userId: userId,
          layer: layer,
          tags: tags,
          limit: limitPerLayer,
        ),
      ),
    );

    return results.expand((entries) => entries).toList();
  }

  Future<void> touchLastUsed(String userId, KnowledgeEntry entry) async {
    await _entriesRef(userId, entry.layer).doc(entry.id).set(
      {'lastUsedAt': DateTime.now().toIso8601String()},
      SetOptions(merge: true),
    );
  }

  Future<void> deleteEntry({
    required String userId,
    required String layer,
    required String entryId,
  }) async {
    await _entriesRef(userId, layer).doc(entryId).delete();
  }
}