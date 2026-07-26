import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'knowledge_entry.dart';

class KnowledgeRepository {
  KnowledgeRepository._internal();
  static final KnowledgeRepository instance = KnowledgeRepository._internal();

  final _db = FirebaseFirestore.instance;

  /// Vector search requires a single flat collection.
  /// We use: users/{userId}/knowledge_entries/{entryId}
  CollectionReference<Map<String, dynamic>> _entriesRef(String userId) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('knowledge_entries');
  }

  Future<KnowledgeEntry> addEntry({
    required String userId,
    required KnowledgeEntry entry,
  }) async {
    final doc = await _entriesRef(userId).add(entry.toMap());
    return entry.copyWith(id: doc.id);
  }

  // ---------------------------------------------------------------------------
  // Manual Vector Search (RAG) - No cloud_firestore 5.0.0 required
  // ---------------------------------------------------------------------------
  /// Fetches all entries for the user and calculates cosine similarity in memory.
  Future<List<KnowledgeEntry>> vectorSearch({
    required String userId,
    required List<double> queryVector,
    int limit = 10,
  }) async {
    try {
      // 1. Fetch all knowledge entries for the user
      final snapshot = await _entriesRef(userId).get();
      
      if (snapshot.docs.isEmpty) return [];

      final entries = snapshot.docs
          .map((d) => KnowledgeEntry.fromMap(d.id, d.data()))
          .where((e) => e.embedding != null && e.embedding!.length == queryVector.length)
          .toList();

      // 2. Calculate cosine similarity for each entry
      final scoredEntries = <MapEntry<KnowledgeEntry, double>>[];
      for (final entry in entries) {
        final score = _cosineSimilarity(queryVector, entry.embedding!);
        scoredEntries.add(MapEntry(entry, score));
      }

      // 3. Sort by highest similarity score
      scoredEntries.sort((a, b) => b.value.compareTo(a.value));

      // 4. Return top N matches
      return scoredEntries
          .take(limit)
          .map((mapEntry) => mapEntry.key)
          .toList();
          
    } catch (e) {
      debugPrint('KnowledgeRepository.vectorSearch failed: $e');
      return [];
    }
  }

  /// Standard mathematical formula for Cosine Similarity.
  double _cosineSimilarity(List<double> a, List<double> b) {
    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;
    
    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    
    if (normA <= 0 || normB <= 0) return 0.0;
    return dotProduct / (sqrt(normA) * sqrt(normB));
  }

  // ---------------------------------------------------------------------------
  // Existing / Adapted Queries
  // ---------------------------------------------------------------------------
  Future<List<KnowledgeEntry>> queryLayer({
    required String userId,
    required String layer,
    required List<String> tags,
    int limit = 5,
  }) async {
    if (tags.isEmpty) return [];

    final tagsToMatch = tags.take(10).toList();

    try {
      final snapshot = await _entriesRef(userId)
          .where('layer', isEqualTo: layer)
          .where('tags', arrayContainsAny: tagsToMatch)
          .orderBy('importance', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs
          .map((d) => KnowledgeEntry.fromMap(d.id, d.data()))
          .toList();
    } on FirebaseException catch (e) {
      if (e.code == 'failed-precondition') {
        debugPrint(
          'KnowledgeRepository.queryLayer: no composite index yet for '
          'layer "$layer" (tags arrayContainsAny + importance orderBy) - '
          'falling back to an unordered fetch. Create the index Firestore '
          'suggests in the error below to get true top-by-importance '
          'ranking instead of this approximation:\n$e',
        );
        return _queryLayerWithoutIndex(userId, layer, tagsToMatch, limit);
      }
      debugPrint('KnowledgeRepository.queryLayer: layer "$layer" failed: $e');
      return [];
    } catch (e) {
      debugPrint('KnowledgeRepository.queryLayer: layer "$layer" failed: $e');
      return [];
    }
  }

  Future<List<KnowledgeEntry>> _queryLayerWithoutIndex(
    String userId,
    String layer,
    List<String> tags,
    int limit,
  ) async {
    final snapshot = await _entriesRef(userId)
        .where('layer', isEqualTo: layer)
        .where('tags', arrayContainsAny: tags)
        .get();

    final entries = snapshot.docs
        .map((d) => KnowledgeEntry.fromMap(d.id, d.data()))
        .toList()
      ..sort((a, b) => b.importance.compareTo(a.importance));

    return entries.take(limit).toList();
  }

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
    if (entry.id.isEmpty) return;

    await _entriesRef(userId).doc(entry.id).set(
      {'lastUsedAt': DateTime.now().toIso8601String()},
      SetOptions(merge: true),
    );
  }

  Future<void> deleteEntry({
    required String userId,
    required String entryId,
  }) async {
    await _entriesRef(userId).doc(entryId).delete();
  }

  /// Deletes all entries in a layer that match ANY of the provided tags.
  Future<void> deleteByTags(
    String userId,
    String layer,
    List<String> tags,
  ) async {
    if (tags.isEmpty) return;

    final snapshot = await _entriesRef(userId)
        .where('layer', isEqualTo: layer)
        .where('tags', arrayContainsAny: tags)
        .get();

    for (final doc in snapshot.docs) {
      await doc.reference.delete();
    }
  }

  /// Fallback: Gets the most recently used facts across ALL layers.
  Future<List<KnowledgeEntry>> getRecentFacts(
    String userId, 
    {int limit = 5}
  ) async {
    final snapshot = await _entriesRef(userId)
        .orderBy('lastUsedAt', descending: true)
        .limit(limit)
        .get();

    if (snapshot.docs.isEmpty) {
      final createdSnapshot = await _entriesRef(userId)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
          
      return createdSnapshot.docs
          .map((d) => KnowledgeEntry.fromMap(d.id, d.data()))
          .toList();
    }

    return snapshot.docs
        .map((d) => KnowledgeEntry.fromMap(d.id, d.data()))
        .toList();
  }

  /// Returns all knowledge entries in a layer (for UI).
  Future<List<KnowledgeEntry>> getAllEntries(
    String userId, 
    String layer
  ) async {
    final snapshot = await _entriesRef(userId)
        .where('layer', isEqualTo: layer)
        .orderBy('createdAt', descending: true)
        .get();

    return snapshot.docs
        .map((doc) => KnowledgeEntry.fromMap(doc.id, doc.data()))
        .toList();
  }

  /// Realtime stream of entries (for UI).
  Stream<List<KnowledgeEntry>> watchEntries(
    String userId, 
    String layer
  ) {
    return _entriesRef(userId)
        .where('layer', isEqualTo: layer)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => KnowledgeEntry.fromMap(doc.id, doc.data()))
            .toList());
  }
}