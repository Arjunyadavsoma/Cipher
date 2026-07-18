import 'knowledge_entry.dart';
import 'knowledge_repository.dart';
import 'layer_classifier_service.dart';

/// Persists new facts (from QueryPlan.thingsToRemember, or any other
/// caller) into the correct knowledge layer. One classification + one
/// write per fact, run concurrently across facts rather than in
/// sequence.
class KnowledgeWriteService {
  KnowledgeWriteService._internal();

  static final KnowledgeWriteService instance =
      KnowledgeWriteService._internal();

  final _repo = KnowledgeRepository.instance;
  final _classifier = LayerClassifierService.instance;

  /// [importance] defaults higher (0.7) than auto-captured facts (0.5)
  /// when the caller knows the user stated this explicitly/deliberately
  /// (e.g. "remember that...") - ranks it above incidentally-mentioned
  /// facts when a retrieval query has more matches than its budget.
  Future<void> saveFacts(
    String userId,
    List<String> facts, {
    double importance = 0.5,
  }) async {
    final cleaned = facts.map((f) => f.trim()).where((f) => f.isNotEmpty);
    if (cleaned.isEmpty) return;

    await Future.wait(cleaned.map((fact) => _saveOne(userId, fact, importance)));
  }

  Future<void> _saveOne(String userId, String fact, double importance) async {
    try {
      final classified = await _classifier.classify(fact);

      await _repo.addEntry(
        userId: userId,
        entry: KnowledgeEntry(
          id: '', // Firestore assigns the id on add()
          layer: classified.layer,
          fact: fact,
          tags: classified.tags,
          importance: importance,
          createdAt: DateTime.now(),
        ),
      );
    } catch (e) {
      // A single fact failing to save shouldn't block the others, and
      // shouldn't surface as a user-facing error - same non-fatal
      // treatment RssController gives a failed source save. Logged
      // (not silent) so a broken write path doesn't look like "nothing
      // happened" - e.g. a Firestore security-rules rejection would
      // otherwise vanish here just as invisibly as retrieval failures did.
      // ignore: avoid_print
      print('KnowledgeWriteService: failed to save fact "$fact": $e');
    }
  }
}