import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mimir_ai/features/agents/models/tool.dart';


/// Generic path-based Firestore access for agents that need arbitrary
/// document/collection reads and writes beyond the fixed
/// users/{uid}/agentContext/{agentId} shape AgentMemoryRepository
/// covers. Registered as 'firebase' - this is what DsaRepository
/// (and any future agent needing free-form Firestore access) actually
/// calls through ToolManager.executeTool('firebase', {...}).
///
/// Path convention follows Firestore's own rule: an even number of
/// '/'-separated segments is a document, an odd number is a
/// collection. 'get'/'set'/'delete' expect a document path;
/// 'collection' expects a collection path. Passing the wrong shape to
/// the wrong operation throws Firestore's own ArgumentError rather
/// than silently doing nothing - callers should get a loud failure,
/// not a quietly-empty read.
class FirebaseTool implements Tool {
  @override
  String get name => 'firebase';

  final _db = FirebaseFirestore.instance;

  @override
  Future<dynamic> execute(Map<String, dynamic> input) async {
    final type = input['type'] as String? ?? '';
    final path = input['path'] as String? ?? '';

    if (path.isEmpty) {
      throw Exception('FirebaseTool: "path" is required');
    }

    switch (type) {
      case 'get':
        return _get(path);
      case 'set':
        return _set(path, input['data'] as Map<String, dynamic>? ?? const {});
      case 'collection':
        return _collection(path);
      case 'delete':
        return _delete(path);
      default:
        throw Exception('FirebaseTool: unknown operation "$type"');
    }
  }

  Future<Map<String, dynamic>?> _get(String path) async {
    final doc = await _db.doc(path).get();
    return doc.data();
  }

  Future<void> _set(String path, Map<String, dynamic> data) async {
    await _db.doc(path).set(data, SetOptions(merge: true));
  }

  /// Returns each document's data with its Firestore doc id folded in
  /// under 'id' - callers like DsaRepository.getSavedQuestions() rely
  /// on that id being present (DsaQuestion.fromMap reads map['id']).
  Future<List<Map<String, dynamic>>> _collection(String path) async {
    final snapshot = await _db.collection(path).get();
    return snapshot.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<void> _delete(String path) async {
    await _db.doc(path).delete();
  }
}