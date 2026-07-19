import 'package:cloud_firestore/cloud_firestore.dart';
import 'knowledge_entry.dart';

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
    return entry.copyWith(id: doc.id);
  }

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

  Future<List<KnowledgeEntry>> _queryLayerWithoutIndex(
    String userId,
    String layer,
    List<String> tags,
    int limit,
  ) async {
    final snapshot = await _entriesRef(userId, layer)
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

  /// Deletes all entries in a layer that match ANY of the provided tags.
  /// Used to overwrite old singular attributes (like job or location) 
  /// when a user states a new fact with the same tags.
  Future<void> deleteByTags(
    String userId,
    String layer,
    List<String> tags,
  ) async {
    if (tags.isEmpty) return;

    final snapshot = await _entriesRef(userId, layer)
        .where('tags', arrayContainsAny: tags)
        .get();

    for (final doc in snapshot.docs) {
      await doc.reference.delete();
    }
  }
    /// Fallback: Gets the most recently used facts across ALL layers.
  /// Used when the planner fails to generate tags.
  Future<List<KnowledgeEntry>> getRecentFacts(String userId, {int limit = 5}) async {
    final results = await Future.wait(
      KnowledgeLayers.all.map((layer) => _entriesRef(userId, layer).get()),
    );

    final allEntries = <KnowledgeEntry>[];
    for (final snapshot in results) {
      allEntries.addAll(snapshot.docs.map((d) => KnowledgeEntry.fromMap(d.id, d.data())));
    }

    // Sort by lastUsedAt (if available), otherwise by createdAt
    allEntries.sort((a, b) {
      final aTime = a.lastUsedAt ?? a.createdAt;
      final bTime = b.lastUsedAt ?? b.createdAt;
      return bTime.compareTo(aTime);
    });

    return allEntries.take(limit).toList();
  }
    /// Returns all knowledge entries in a layer (for UI).
  Future<List<KnowledgeEntry>> getAllEntries(String userId, String layer) async {
    final snapshot = await _entriesRef(userId, layer)
        .orderBy('createdAt', descending: true)
        .get();

    return snapshot.docs
        .map((doc) => KnowledgeEntry.fromMap(doc.id, doc.data()))
        .toList();
  }

  /// Realtime stream of entries (for UI).
  Stream<List<KnowledgeEntry>> watchEntries(String userId, String layer) {
    return _entriesRef(userId, layer)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => KnowledgeEntry.fromMap(doc.id, doc.data()))
            .toList());
  }
}