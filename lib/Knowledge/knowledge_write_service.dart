import 'package:flutter/foundation.dart';
import 'knowledge_entry.dart';
import 'knowledge_repository.dart';
import 'layer_classifier_service.dart';
import 'nvidia_embedding_service.dart';

class KnowledgeWriteService {
  KnowledgeWriteService._internal();
  static final KnowledgeWriteService instance = KnowledgeWriteService._internal();

  final _repo = KnowledgeRepository.instance;
  final _classifier = LayerClassifierService.instance;
  final _embedder = NvidiaEmbeddingService.instance;

  Future<void> saveFacts(String userId, List<String> facts, {double importance = 0.5}) async {
    final cleaned = facts.map((f) => f.trim()).where((f) => f.isNotEmpty);
    if (cleaned.isEmpty) return;

    await Future.wait(cleaned.map((fact) => _saveOne(userId, fact, importance)));
  }

  Future<void> _saveOne(String userId, String fact, double importance) async {
    try {
      final classified = await _classifier.classify(fact);

      // 1. Deduplication Check
      final existing = await _repo.getRecentFacts(userId, limit: 20);
      final factLower = fact.toLowerCase();
      final alreadyExists = existing.any((e) => 
          e.fact.toLowerCase() == factLower || 
          e.fact.toLowerCase().contains(factLower) ||
          factLower.contains(e.fact.toLowerCase()));

      if (alreadyExists) {
        debugPrint('ℹ️ KnowledgeWriteService: Fact already exists, skipping save.');
        return;
      }

      // 2. Delete old conflicting singular attributes
      if (classified.overwrite) {
        await _repo.deleteByTags(userId, classified.layer, classified.tags);
      }

      // 3. Generate Vector Embedding via NVIDIA
      final embedding = await _embedder.embed(fact, isQuery: false);

      // 4. Save to Firestore
      await _repo.addEntry(
        userId: userId,
        entry: KnowledgeEntry(
          id: '',
          layer: classified.layer,
          fact: fact,
          tags: classified.tags,
          importance: importance,
          createdAt: DateTime.now(),
          embedding: embedding,
        ),
      );
    } catch (e) {
      debugPrint('❌ KnowledgeWriteService: failed to save fact "$fact": $e');
    }
  }
}