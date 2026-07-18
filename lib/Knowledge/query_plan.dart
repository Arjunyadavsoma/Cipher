/// Parsed result of QueryPlannerService's single classification call.
///
/// Replaces the old two-call IntentGate -> IntentClassifier flow: agent
/// routing, required-knowledge tags, and new facts to remember all come
/// back from one JSON response instead of two separate Groq calls.
class QueryPlan {
  final String agentName;
  final double confidence;

  /// Tags used to look up relevant KnowledgeEntry rows across layers
  /// (e.g. ["job", "email_style"]). Kept short - Firestore's
  /// arrayContainsAny caps at 10 values per query, and a tight tag list
  /// also keeps retrieval precise instead of pulling in everything.
  final List<String> requiredKnowledgeTags;

  /// New facts the planner noticed in this message that are worth
  /// persisting (e.g. "User's manager is named Raj"). Empty when
  /// nothing new/memorable was said.
  final List<String> thingsToRemember;

  /// The user's message, possibly lightly cleaned (e.g. filler removed)
  /// - passed on to the agent instead of the raw message when non-empty.
  final String cleanedQuery;

  const QueryPlan({
    required this.agentName,
    required this.confidence,
    this.requiredKnowledgeTags = const [],
    this.thingsToRemember = const [],
    this.cleanedQuery = '',
  });

  factory QueryPlan.fromJson(Map<String, dynamic> json, String fallbackQuery) {
    return QueryPlan(
      agentName: json['agent'] as String? ?? 'Default Chat Agent',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      requiredKnowledgeTags:
          List<String>.from(json['requiredKnowledgeTags'] as List? ?? const []),
      thingsToRemember:
          List<String>.from(json['thingsToRemember'] as List? ?? const []),
      cleanedQuery: (json['query'] as String?)?.trim().isNotEmpty == true
          ? json['query'] as String
          : fallbackQuery,
    );
  }

  /// Fallback plan used when the planner call fails outright - mirrors
  /// IntentClassifier's existing fail-safe (default to Default Chat
  /// Agent, confidence 0.0) rather than throwing and blocking the user.
  factory QueryPlan.fallback(String message) {
    return QueryPlan(
      agentName: 'Default Chat Agent',
      confidence: 0.0,
      cleanedQuery: message,
    );
  }
}
