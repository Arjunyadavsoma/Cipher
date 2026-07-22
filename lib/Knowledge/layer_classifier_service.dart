import 'dart:convert';
import '../../../core/services/groq/chat_service.dart';
import 'knowledge_entry.dart';

class LayerClassifierService {
  LayerClassifierService._internal();
  static final LayerClassifierService instance = LayerClassifierService._internal();

  static const String _systemPrompt =
      "You are an enterprise knowledge graph classifier. You output exactly one JSON object. Never add explanation.";

    Future<ClassifiedFact> classify(String fact) async {
    final tagList = KnowledgeTaxonomy.allTags.map((t) => '"$t"').join(', ');
    
    final prompt = "Fact: \"$fact\"\n\n"
        "Classify this fact. Choose 1-2 tags from this EXACT list: [$tagList].\n"
        "Do not use any other tags. If it's about an interview or DSA, use \"interview_prep\" or \"dsa_topic\".\n"
        "If it's about an email rule or script, use \"email_rule\" or \"script\".\n\n"
        "Return JSON only:\n"
        '{"tags":["tag1","tag2"]}';

    try {
      final response = await ChatService.instance.sendMessage(
        message: prompt,
        history: const [],
        systemPrompt: _systemPrompt,
        temperature: 0,
      );

      final jsonStr = _extractJson(response);
      final parsed = jsonDecode(jsonStr) as Map<String, dynamic>;

      final rawTags = List<String>.from(parsed['tags'] as List? ?? const []);
      
      // Filter out any hallucinated tags not in our strict dictionary
      var validTags = rawTags
          .map((t) => t.toString().toLowerCase().trim())
          .where((t) => KnowledgeTaxonomy.allTags.contains(t))
          .toSet()
          .toList();

      // ┌─────────────────────────────────────────────────────────┐
      // │ SMART FALLBACK: If LLM fails, guess based on keywords   │
      // └─────────────────────────────────────────────────────────┘
      if (validTags.isEmpty) {
        final factLower = fact.toLowerCase();
        if (factLower.contains('dsa') || factLower.contains('interview') || factLower.contains('algorithm')) {
          validTags.add(KnowledgeTaxonomy.dsaTopic);
        } else if (factLower.contains('project') || factLower.contains('app') || factLower.contains('code')) {
          validTags.add(KnowledgeTaxonomy.project);
        } else if (factLower.contains('job') || factLower.contains('work') || factLower.contains('engineer')) {
          validTags.add(KnowledgeTaxonomy.currentJob);
        } else {
          validTags.add('hobby'); // Ultimate fallback
        }
      }

      // Deterministic logic: The tag decides the layer and overwrite status
      final primaryTag = validTags.first;
      final layer = KnowledgeTaxonomy.layerForTag(primaryTag);
      final overwrite = KnowledgeTaxonomy.isAttribute(primaryTag);

      return ClassifiedFact(
        layer: layer,
        tags: validTags,
        overwrite: overwrite,
      );
    } catch (_) {
      return ClassifiedFact(
        layer: KnowledgeLayers.general,
        tags: [KnowledgeTaxonomy.hobby],
        overwrite: false,
      );
    }
  }

  String _extractJson(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start == -1 || end == -1) return '{}';
    return text.substring(start, end + 1);
  }
}

class ClassifiedFact {
  final String layer;
  final List<String> tags;
  final bool overwrite;

  const ClassifiedFact({
    required this.layer,
    required this.tags,
    required this.overwrite,
  });
}