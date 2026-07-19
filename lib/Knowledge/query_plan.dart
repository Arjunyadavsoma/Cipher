class QueryPlan {
  final String agentName;
  final double confidence;
  final List<String> requiredKnowledgeTags;
  final List<String> thingsToRemember;
  final List<String> thingsToForget; // <-- NEW
  final String cleanedQuery;

  const QueryPlan({
    required this.agentName,
    required this.confidence,
    this.requiredKnowledgeTags = const [],
    this.thingsToRemember = const [],
    this.thingsToForget = const [], // <-- NEW
    this.cleanedQuery = '',
  });

  factory QueryPlan.fromJson(Map<String, dynamic> json, String fallbackQuery) {
    final tags = json["requiredKnowledgeTags"];
    final memories = json["thingsToRemember"];
    final forgets = json["thingsToForget"]; // <-- NEW

    List<String> normalizeTags(List? raw) {
      if (raw == null) return const [];
      return raw.map((e) => e.toString().toLowerCase().trim()).where((t) => t.isNotEmpty).toList();
    }

    return QueryPlan(
      agentName: (json["agent"] ?? "Default Chat Agent").toString(),
      confidence: (json["confidence"] is num) ? (json["confidence"] as num).toDouble() : 0.0,
      requiredKnowledgeTags: normalizeTags(tags is List ? tags : null),
      thingsToRemember: memories is List ? memories.map((e) => e.toString()).toList() : const [],
      thingsToForget: forgets is List ? forgets.map((e) => e.toString()).toList() : const [], // <-- NEW
      cleanedQuery: (json["query"]?.toString().trim().isNotEmpty ?? false) ? json["query"].toString() : fallbackQuery,
    );
  }

  factory QueryPlan.fallback(String message) {
    return QueryPlan(
      agentName: 'Default Chat Agent',
      confidence: 0.0,
      cleanedQuery: message,
    );
  }
}