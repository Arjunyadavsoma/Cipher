import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cipher_ai/Knowledge/knowledge_entry.dart';
import 'package:cipher_ai/Knowledge/knowledge_Screen/knowledge_detail_page.dart'
    as knowledge;
import 'package:cipher_ai/Knowledge/knowledge_Screen/knowledge_provider.dart';
import 'package:cipher_ai/Knowledge/knowledge_Screen/add_knowledge_sheet.dart';
import 'package:cipher_ai/Knowledge/knowledge_Screen/knowledge_detail_page.dart';

class KnowledgePage extends ConsumerWidget {
  const KnowledgePage({super.key});

  String _capitalize(String text) {
    if (text.isEmpty) return text;
    return "${text[0].toUpperCase()}${text.substring(1)}";
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedLayer = ref.watch(selectedKnowledgeLayerProvider);
    final layers = ref.watch(knowledgeLayersProvider);
    final entries = ref.watch(filteredKnowledgeEntriesProvider);
    final uid = ref.watch(userIdProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Explore Memory',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        onPressed: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.white,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            builder: (context) => AddKnowledgeSheet(
              onSave: (text) async {
                await ref.read(knowledgeWriteServiceProvider).saveFacts(uid!, [
                  text,
                ], importance: 0.8);
              },
            ),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text("Add Memory"),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search memories...',
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (value) {
                ref.read(knowledgeSearchQueryProvider.notifier).state = value;
              },
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: layers.length,
              itemBuilder: (context, index) {
                final layer = layers[index];
                final selected = layer == selectedLayer;

                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: GestureDetector(
                    onTap: () {
                      ref.read(selectedKnowledgeLayerProvider.notifier).state =
                          layer;
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: selected ? Colors.black : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _capitalize(layer),
                        style: TextStyle(
                          color: selected ? Colors.white : Colors.black54,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.memory,
                          size: 48,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No memories in this layer yet.',
                          style: TextStyle(color: Colors.grey.shade400),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: entries.length,
                    separatorBuilder: (context, index) => Divider(
                      indent: 90,
                      height: 1,
                      color: Colors.grey.shade100,
                    ),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return _AppStoreTile(entry: entry);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _AppStoreTile extends StatelessWidget {
  final KnowledgeEntry entry;
  const _AppStoreTile({required this.entry});

  IconData _iconForLayer(String layer) {
    switch (layer) {
      case 'professional':
        return Icons.work_outline;
      case 'technical':
        return Icons.code;
      case 'projects':
        return Icons.folder_open;
      case 'personal':
        return Icons.person_outline;
      case 'preferences':
        return Icons.tune;
      case 'education':
        return Icons.school_outlined;
      case 'schedule':
        return Icons.calendar_month_outlined;
      case 'automations':
        return Icons.bolt_outlined;
      default:
        return Icons.lightbulb_outline;
    }
  }

  Color _colorForLayer(String layer) {
    switch (layer) {
      case 'professional':
        return Colors.blue.shade50;
      case 'technical':
        return Colors.purple.shade50;
      case 'projects':
        return Colors.orange.shade50;
      case 'personal':
        return Colors.green.shade50;
      case 'preferences':
        return Colors.pink.shade50;
      case 'education':
        return Colors.yellow.shade50;
      case 'schedule':
        return Colors.red.shade50;
      case 'automations':
        return Colors.teal.shade50;
      default:
        return Colors.grey.shade100;
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => KnowledgeDetailPage(entry: entry),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: _colorForLayer(entry.layer),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _iconForLayer(entry.layer),
                color: Colors.black54,
                size: 28,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.fact,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (entry.tags.isNotEmpty)
                    Text(
                      entry.tags.map((t) => '#$t').join('  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade500,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 8.0, top: 4.0),
              child: Text(
                "${(entry.importance * 100).toInt()}%",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
