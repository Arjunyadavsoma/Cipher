import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mimir_ai/Knowledge/knowledge_entry.dart';
import 'package:mimir_ai/Knowledge/knowledge_Screen/knowledge_repository.dart';

/// Repository
final knowledgeRepositoryProvider =
    Provider<KnowledgeRepository>((ref) {
  return KnowledgeRepository.instance;
});

/// Available knowledge layers
final knowledgeLayersProvider =
    FutureProvider<List<String>>((ref) async {
  return ref
      .read(knowledgeRepositoryProvider)
      .getKnowledgeLayers();
});

/// Selected layer
final selectedKnowledgeLayerProvider =
    StateProvider<String>(
  (ref) => KnowledgeLayers.personal,
);

/// Live entries
final knowledgeEntriesProvider =
    StreamProvider<List<KnowledgeEntry>>((ref) {
  final layer = ref.watch(selectedKnowledgeLayerProvider);

  return ref
      .read(knowledgeRepositoryProvider)
      .watchEntries(layer);
});

/// Search text
final knowledgeSearchQueryProvider =
    StateProvider<String>((ref) => '');

/// Filtered entries
final filteredKnowledgeEntriesProvider =
    Provider<List<KnowledgeEntry>>((ref) {
  final entries =
      ref.watch(knowledgeEntriesProvider).value ?? [];

  final query = ref
      .watch(knowledgeSearchQueryProvider)
      .trim()
      .toLowerCase();

  if (query.isEmpty) {
    return entries;
  }

  return entries.where((entry) {
    final matchesFact =
        entry.fact.toLowerCase().contains(query);

    final matchesTag = entry.tags.any(
      (tag) => tag.toLowerCase().contains(query),
    );

    final matchesLayer =
        entry.layer.toLowerCase().contains(query);

    return matchesFact ||
        matchesTag ||
        matchesLayer;
  }).toList();
});