import 'package:cipher_ai/Knowledge/knowledge_entry.dart';

class ContextCompressor {
  /// Compresses and formats retrieved knowledge entries to save tokens 
  /// and prevent redundant information from reaching the LLM.
  String compress(List<KnowledgeEntry> entries) {
    if (entries.isEmpty) return '';

    final seenFacts = <String>{};
    final byLayer = <String, List<String>>{};

    for (final entry in entries) {
      final factLower = entry.fact.toLowerCase().trim();
      
      // Simple deduplication: skip if we've seen an identical or very similar fact
      if (seenFacts.any((seen) => seen.contains(factLower) || factLower.contains(seen))) {
        continue;
      }
      seenFacts.add(factLower);

      byLayer.putIfAbsent(entry.layer, () => []);
      byLayer[entry.layer]!.add(entry.fact);
    }

    final buffer = StringBuffer();
    buffer.writeln('Background Knowledge (Use only the facts relevant to the current question):');
    
    for (final layer in byLayer.keys) {
      buffer.writeln('\n[$layer]');
      for (final fact in byLayer[layer]!) {
        buffer.writeln('- $fact');
      }
    }

    return buffer.toString().trim();
  }
}