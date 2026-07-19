import 'dart:convert';
import '../../../core/services/groq/chat_service.dart';
import 'knowledge_entry.dart';

class LayerClassifierService {
  LayerClassifierService._internal();
  static final LayerClassifierService instance = LayerClassifierService._internal();

  static const String _systemPrompt =
      "You are an enterprise knowledge graph classifier. You output exactly one JSON object. Never add explanation.";

  Future<ClassifiedFact> classify(String fact) async {
    // Provide the strict list to the LLM
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
      final validTags = rawTags
          .map((t) => t.toString().toLowerCase().trim())
          .where((t) => KnowledgeTaxonomy.allTags.contains(t))
          .toSet()
          .toList();

      if (validTags.isEmpty) {
        // Fallback: If the LLM fails, dump it in general with no tags
        return ClassifiedFact(
          layer: KnowledgeLayers.general,
          tags: [],
          overwrite: false,
        );
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
        tags: [],
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