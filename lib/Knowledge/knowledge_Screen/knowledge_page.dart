import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mimir_ai/Knowledge/knowledge_entry.dart';

import 'knowledge_provider.dart';

class KnowledgePage extends ConsumerWidget {
  const KnowledgePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedLayer = ref.watch(selectedKnowledgeLayerProvider);
    final layers = ref.watch(knowledgeLayersProvider);
    final entries = ref.watch(filteredKnowledgeEntriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Knowledge'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Add Knowledge (Coming Soon)'),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),

          // Search
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search knowledge...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                ref
                    .read(knowledgeSearchQueryProvider.notifier)
                    .state = value;
              },
            ),
          ),

          const SizedBox(height: 16),

          // Layers
          SizedBox(
            height: 52,
            child: layers.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(e.toString())),
              data: (layerList) {
                return ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: layerList.length,
                  itemBuilder: (context, index) {
                    final layer = layerList[index];

                    final selected =
                        layer == selectedLayer;

                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(layer),
                        selected: selected,
                        onSelected: (_) {
                          ref
                              .read(
                                selectedKnowledgeLayerProvider
                                    .notifier,
                              )
                              .state = layer;
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),

          const Divider(height: 24),

          Expanded(
            child: entries.isEmpty
                ? const Center(
                    child: Text(
                      'No knowledge found.',
                    ),
                  )
                : ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];

                      return _KnowledgeTile(entry: entry);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _KnowledgeTile extends StatelessWidget {
  final KnowledgeEntry entry;

  const _KnowledgeTile({
    required this.entry,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 6,
      ),
      child: ListTile(
        leading: const Icon(Icons.memory),
        title: Text(entry.fact),
        subtitle: entry.tags.isEmpty
            ? null
            : Wrap(
                spacing: 6,
                children: entry.tags
                    .map(
                      (tag) => Chip(
                        label: Text(tag),
                        visualDensity:
                            VisualDensity.compact,
                      ),
                    )
                    .toList(),
              ),
        trailing: Text(
          entry.importance.toStringAsFixed(2),
        ),
      ),
    );
  }
}
