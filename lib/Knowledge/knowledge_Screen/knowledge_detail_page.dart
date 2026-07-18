import 'package:flutter/material.dart';
import 'package:mimir_ai/Knowledge/knowledge_entry.dart';


class KnowledgeDetailPage extends StatelessWidget {
  const KnowledgeDetailPage({
    super.key,
    required this.entry,
  });

  final KnowledgeEntry entry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Knowledge"),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                entry.fact,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),

          const SizedBox(height: 20),

          Text(
            "Layer",
            style: Theme.of(context).textTheme.titleSmall,
          ),

          const SizedBox(height: 8),

          Chip(
            label: Text(entry.layer),
          ),

          const SizedBox(height: 20),

          Text(
            "Tags",
            style: Theme.of(context).textTheme.titleSmall,
          ),

          const SizedBox(height: 8),

          if (entry.tags.isEmpty)
            const Text("No tags")
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: entry.tags
                  .map(
                    (tag) => Chip(
                      label: Text(tag),
                    ),
                  )
                  .toList(),
            ),

          const SizedBox(height: 20),

          Text(
            "Importance",
            style: Theme.of(context).textTheme.titleSmall,
          ),

          const SizedBox(height: 8),

          LinearProgressIndicator(
            value: entry.importance,
            minHeight: 8,
            borderRadius: BorderRadius.circular(8),
          ),

          const SizedBox(height: 8),

          Text(
            "${(entry.importance * 100).toStringAsFixed(0)}%",
          ),

          const SizedBox(height: 20),

          Text(
            "Created",
            style: Theme.of(context).textTheme.titleSmall,
          ),

          const SizedBox(height: 6),

          Text(
            entry.createdAt.toLocal().toString(),
          ),

          const SizedBox(height: 20),

          Text(
            "Last Used",
            style: Theme.of(context).textTheme.titleSmall,
          ),

          const SizedBox(height: 6),

          Text(
            entry.lastUsedAt == null
                ? "Never"
                : entry.lastUsedAt!.toLocal().toString(),
          ),
        ],
      ),
    );
  }
}