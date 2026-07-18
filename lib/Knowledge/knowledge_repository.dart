import 'package:cloud_firestore/cloud_firestore.dart';

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
  Future<List<KnowledgeEntry>> queryLayer({
    required String userId,
    required String layer,
    required List<String> tags,
    int limit = 5,
  }) async {
    if (tags.isEmpty) return [];

    final snapshot = await _entriesRef(userId, layer)
        .where('tags', arrayContainsAny: tags.take(10).toList())
        .orderBy('importance', descending: true)
        .limit(limit)
        .get();

    return snapshot.docs
        .map((d) => KnowledgeEntry.fromMap(d.id, d.data()))
        .toList();
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
