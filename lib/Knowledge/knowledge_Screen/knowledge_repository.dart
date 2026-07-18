import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mimir_ai/Knowledge/knowledge_entry.dart';

class KnowledgeRepository {
  KnowledgeRepository._();

  static final KnowledgeRepository instance = KnowledgeRepository._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _uid {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User is not authenticated.');
    }
    return user.uid;
  }

  CollectionReference<Map<String, dynamic>> _entries(String layer) {
    return _firestore
        .collection('users')
        .doc(_uid)
        .collection('knowledge')
        .doc(layer)
        .collection('entries');
  }

  /// Returns all knowledge entries in a layer.
  Future<List<KnowledgeEntry>> getAllEntries(String layer) async {
    final snapshot = await _entries(layer)
        .orderBy('createdAt', descending: true)
        .get();

    return snapshot.docs
        .map(
          (doc) => KnowledgeEntry.fromMap(
            doc.id,
            doc.data(),
          ),
        )
        .toList();
  }

  /// Realtime stream of entries.
  Stream<List<KnowledgeEntry>> watchEntries(String layer) {
    return _entries(layer)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(
                (doc) => KnowledgeEntry.fromMap(
                  doc.id,
                  doc.data(),
                ),
              )
              .toList(),
        );
  }

  /// Get a single entry.
  Future<KnowledgeEntry?> getEntry(
    String layer,
    String entryId,
  ) async {
    final doc = await _entries(layer).doc(entryId).get();

    if (!doc.exists || doc.data() == null) {
      return null;
    }

    return KnowledgeEntry.fromMap(
      doc.id,
      doc.data()!,
    );
  }

  /// Create a new entry.
  Future<void> addEntry(
    String layer,
    KnowledgeEntry entry,
  ) async {
    await _entries(layer).doc(entry.id).set(entry.toMap());
  }

  /// Update an existing entry.
  Future<void> updateEntry(
    String layer,
    KnowledgeEntry entry,
  ) async {
    await _entries(layer).doc(entry.id).update(entry.toMap());
  }

  /// Delete an entry.
  Future<void> deleteEntry(
    String layer,
    String entryId,
  ) async {
    await _entries(layer).doc(entryId).delete();
  }

  /// Updates lastUsedAt.
  Future<void> touchLastUsed(
    String layer,
    String entryId,
  ) async {
    await _entries(layer).doc(entryId).update({
      'lastUsedAt': DateTime.now().toIso8601String(),
    });
  }

  /// Search entries by fact.
  Future<List<KnowledgeEntry>> searchByFact(
    String layer,
    String query,
  ) async {
    final entries = await getAllEntries(layer);

    final q = query.toLowerCase();

    return entries.where((entry) {
      return entry.fact.toLowerCase().contains(q);
    }).toList();
  }

  /// Search entries by tags.
  Future<List<KnowledgeEntry>> searchByTags(
    String layer,
    List<String> tags,
  ) async {
    final entries = await getAllEntries(layer);

    return entries.where((entry) {
      return entry.tags.any(tags.contains);
    }).toList();
  }

  /// Returns all available knowledge layers.
  Future<List<String>> getKnowledgeLayers() async {
    final snapshot = await _firestore
        .collection('users')
        .doc(_uid)
        .collection('knowledge')
        .get();

    return snapshot.docs.map((doc) => doc.id).toList();
  }
}