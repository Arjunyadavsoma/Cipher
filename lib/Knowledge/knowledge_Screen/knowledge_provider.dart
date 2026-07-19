import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mimir_ai/Knowledge/knowledge_entry.dart';
import 'package:mimir_ai/Knowledge/knowledge_repository.dart';
import 'package:mimir_ai/Knowledge/knowledge_write_service.dart';

/// Repository
final knowledgeRepositoryProvider = Provider<KnowledgeRepository>((ref) {
  return KnowledgeRepository.instance;
});

/// Write Service (for manually adding facts from UI)
final knowledgeWriteServiceProvider = Provider<KnowledgeWriteService>((ref) {
  return KnowledgeWriteService.instance;
});

/// Current User ID
final userIdProvider = Provider<String?>((ref) {
  return FirebaseAuth.instance.currentUser?.uid;
});

/// Available knowledge layers
final knowledgeLayersProvider = Provider<List<String>>((ref) {
  return KnowledgeLayers.all;
});

/// Selected layer
final selectedKnowledgeLayerProvider = StateProvider<String>((ref) {
  return KnowledgeLayers.personal;
});

/// Live entries stream
final knowledgeEntriesProvider = StreamProvider<List<KnowledgeEntry>>((ref) {
  final uid = ref.watch(userIdProvider);
  final layer = ref.watch(selectedKnowledgeLayerProvider);
  if (uid == null) return Stream.value([]);

  return ref.read(knowledgeRepositoryProvider).watchEntries(uid, layer);
});

/// Search text
final knowledgeSearchQueryProvider = StateProvider<String>((ref) => '');

/// Filtered entries
final filteredKnowledgeEntriesProvider = Provider<List<KnowledgeEntry>>((ref) {
  final entries = ref.watch(knowledgeEntriesProvider).value ?? [];
  final query = ref.watch(knowledgeSearchQueryProvider).trim().toLowerCase();

  if (query.isEmpty) return entries;

  return entries.where((entry) {
    final matchesFact = entry.fact.toLowerCase().contains(query);
    final matchesTag = entry.tags.any((tag) => tag.toLowerCase().contains(query));
    return matchesFact || matchesTag;
  }).toList();
});