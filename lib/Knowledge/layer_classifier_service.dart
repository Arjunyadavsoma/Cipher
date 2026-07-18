import 'dart:convert';

import '../../../core/services/groq/chat_service.dart';
import 'knowledge_entry.dart';

/// Decides which fixed layer a new fact belongs to, plus a short tag
/// list for it. A single cheap Groq call per fact (temperature 0.1,
/// JSON-only), same pattern as IntentGate's one-word classification -
/// kept as its own service rather than folded into QueryPlannerService
/// because facts can also arrive from places other than a live user
/// message (e.g. a bulk import), and shouldn't require routing an
/// entire agent request to get classified.
class LayerClassifierService {
  LayerClassifierService._internal();

  static final LayerClassifierService instance =
      LayerClassifierService._internal();

  static const String _systemPrompt =
      "You are a knowledge-filing classifier, not a conversational "
      "assistant. You only ever output a single JSON object matching "
      "the schema you are given. Never add explanation or extra text.";

  Future<ClassifiedFact> classify(String fact) async {
    final prompt = "Knowledge layers: personal, professional, preferences, "
        "technical, projects, general.\n\n"
        "Fact: \"$fact\"\n\n"
        "Pick the single best-fitting layer, and give 1-4 short lowercase "
        "tags (single words or short phrases, e.g. \"job\", "
        "\"email_style\") that would help retrieve this fact later.\n\n"
        "Return JSON only, no other text:\n"
        '{"layer":"<layer>","tags":["tag1","tag2"]}';

    try {
      final response = await ChatService.instance.sendMessage(
        message: prompt,
        history: const [],
        systemPrompt: _systemPrompt,
        temperature: 0.1,
      );

      final jsonStr = _extractJson(response);
      final parsed = jsonDecode(jsonStr) as Map<String, dynamic>;

      final layer = parsed['layer'] as String? ?? KnowledgeLayers.general;
      final tags = List<String>.from(parsed['tags'] as List? ?? const []);

      return ClassifiedFact(
        layer: KnowledgeLayers.all.contains(layer)
            ? layer
            : KnowledgeLayers.general,
        tags: tags,
      );
    } catch (_) {
      // Fail-safe: file under "general" with a keyword-derived tag rather
      // than dropping the fact entirely - a coarsely-filed fact is still
      // retrievable later; a lost one isn't.
      return ClassifiedFact(
        layer: KnowledgeLayers.general,
        tags: _fallbackTags(fact),
      );
    }
  }

  List<String> _fallbackTags(String fact) {
    final words = fact
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 3)
        .take(3)
        .toList();
    return words;
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

  const ClassifiedFact({required this.layer, required this.tags});
}
