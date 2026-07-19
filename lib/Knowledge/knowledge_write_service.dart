import 'knowledge_entry.dart';
import 'knowledge_repository.dart';
import 'layer_classifier_service.dart';

class KnowledgeWriteService {
  KnowledgeWriteService._internal();
  static final KnowledgeWriteService instance = KnowledgeWriteService._internal();

  final _repo = KnowledgeRepository.instance;
  final _classifier = LayerClassifierService.instance;

  Future<void> saveFacts(String userId, List<String> facts, {double importance = 0.5}) async {
    final cleaned = facts.map((f) => f.trim()).where((f) => f.isNotEmpty);
    if (cleaned.isEmpty) return;

    await Future.wait(cleaned.map((fact) => _saveOne(userId, fact, importance)));
  }

    Future<void> _saveOne(String userId, String fact, double importance) async {
    try {
      final classified = await _classifier.classify(fact);

      // ┌─────────────────────────────────────────────────────────┐
      // │ DEDUPLICATION: Check if this fact or a similar one      │
      // │ already exists in this layer before saving.             │
      // └─────────────────────────────────────────────────────────┘
      final existing = await _repo.queryLayer(
        userId: userId, 
        layer: classified.layer, 
        tags: classified.tags, 
        limit: 10,
      );
      
      // Simple string matching for deduplication
      final factLower = fact.toLowerCase();
      final alreadyExists = existing.any((e) => 
          e.fact.toLowerCase() == factLower || 
          e.fact.toLowerCase().contains(factLower) ||
          factLower.contains(e.fact.toLowerCase()));

      if (alreadyExists) {
        print('ℹ️ KnowledgeWriteService: Fact already exists, skipping save.');
        return; // Don't save duplicates
      }

      if (classified.overwrite) {
        await _repo.deleteByTags(userId, classified.layer, classified.tags);
      }

      await _repo.addEntry(
        userId: userId,
        entry: KnowledgeEntry(
          id: '',
          layer: classified.layer,
          fact: fact,
          tags: classified.tags,
          importance: importance,
          createdAt: DateTime.now(),
        ),
      );
    } catch (e) {
      print('KnowledgeWriteService: failed to save fact "$fact": $e');
    }
  }
}