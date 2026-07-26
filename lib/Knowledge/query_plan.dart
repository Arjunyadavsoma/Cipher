class QueryPlan {
  final String agentName;
  final double confidence;
  final List<String> thingsToRemember;
  final List<String> thingsToForget;
  final String cleanedQuery;

  const QueryPlan({
    required this.agentName,
    required this.confidence,
    this.thingsToRemember = const [],
    this.thingsToForget = const [],
    this.cleanedQuery = '',
  });

  factory QueryPlan.fromJson(
    Map<String, dynamic> json,
    String fallbackQuery,
    Set<String> validAgentNames,
  ) {
    final memories = json["thingsToRemember"];
    final forgets = json["thingsToForget"];

    // Fallback to Default Chat Agent if the LLM hallucinates an agent name
    final parsedAgent = (json["agent"] ?? "Default Chat Agent").toString();
    final agentName = validAgentNames.contains(parsedAgent) ? parsedAgent : "Default Chat Agent";

    return QueryPlan(
      agentName: agentName,
      confidence: (json["confidence"] is num) ? (json["confidence"] as num).toDouble() : 0.0,
      thingsToRemember: memories is List ? memories.map((e) => e.toString()).toList() : const [],
      thingsToForget: forgets is List ? forgets.map((e) => e.toString()).toList() : const [],
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