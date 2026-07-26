import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cipher_ai/Knowledge/knowledge_entry.dart';
import 'package:cipher_ai/Knowledge/knowledge_Screen/knowledge_provider.dart';

class KnowledgeDetailPage extends ConsumerWidget {
  const KnowledgeDetailPage({super.key, required this.entry});
  final KnowledgeEntry entry;

  String _capitalize(String text) {
    if (text.isEmpty) return text;
    return "${text[0].toUpperCase()}${text.substring(1)}";
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(userIdProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          "Memory Detail",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: () async {
              if (uid == null) return; // Null check safety

              await ref
                  .read(knowledgeRepositoryProvider)
                  .deleteEntry(
                    userId: uid,
                    entryId: entry.id, // Removed the 'layer' parameter
                  );
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            entry.fact,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              height: 1.3,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 32),

          _SectionTitle("Layer"),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _capitalize(entry.layer),
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),

          const SizedBox(height: 24),

          if (entry.tags.isNotEmpty) ...[
            _SectionTitle("Tags"),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: entry.tags
                  .map(
                    (tag) => Chip(
                      label: Text('#$tag'),
                      backgroundColor: Colors.grey.shade100,
                      side: BorderSide.none,
                      labelStyle: const TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 24),
          ],

          _SectionTitle("Importance"),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: entry.importance,
              minHeight: 8,
              backgroundColor: Colors.grey.shade200,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "${(entry.importance * 100).toStringAsFixed(0)}%",
            style: TextStyle(
              color: Colors.grey.shade600,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 32),

          _RowDetail(
            title: "Created",
            value: entry.createdAt.toLocal().toString().split('.').first,
          ),
          const SizedBox(height: 16),
          _RowDetail(
            title: "Last Used",
            value: entry.lastUsedAt == null
                ? "Never"
                : entry.lastUsedAt!.toLocal().toString().split('.').first,
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 13,
        color: Colors.grey.shade500,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _RowDetail extends StatelessWidget {
  final String title;
  final String value;
  const _RowDetail({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade500,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 16, color: Colors.black87),
        ),
      ],
    );
  }
}