import 'package:cloud_firestore/cloud_firestore.dart';

class EntityRepository {
  final _db = FirebaseFirestore.instance;

  /// Links an entity (e.g., "Flutter") to a specific memory entry ID.
  Future<void> linkEntityToMemory({
    required String userId,
    required String entityName,
    required String memoryId,
  }) async {
    final ref = _db.collection('users').doc(userId).collection('entities').doc(entityName.toLowerCase());
    
    await ref.set({
      'name': entityName,
      'memoryIds': FieldValue.arrayUnion([memoryId]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Fetches all memory IDs associated with an entity.
  Future<Set<String>> getMemoryIdsForEntity(String userId, String entityName) async {
    final doc = await _db.collection('users').doc(userId).collection('entities').doc(entityName.toLowerCase()).get();
    
    if (!doc.exists) return {};
    final ids = doc.data()?['memoryIds'] as List? ?? [];
    return ids.map((e) => e.toString()).toSet();
  }
}