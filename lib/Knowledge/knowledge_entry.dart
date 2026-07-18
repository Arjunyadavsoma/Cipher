/// A single atomic fact stored under a knowledge layer
/// (users/{uid}/knowledge/{layer}/entries/{entryId}).
///
/// Kept deliberately short ("Works as backend eng at Stripe", not a
/// paragraph) - this is what makes tag-based retrieval cheap and keeps
/// injected prompt context small. One idea per entry.
class KnowledgeEntry {
  final String id;
  final String layer;
  final String fact;
  final List<String> tags;

  /// 0-1. Used to rank/trim when more matches exist than the retrieval
  /// budget allows. Defaults to 0.5 for auto-captured facts; can be
  /// bumped for facts the user stated explicitly ("remember that...").
  final double importance;

  final DateTime createdAt;
  final DateTime? lastUsedAt;

  const KnowledgeEntry({
    required this.id,
    required this.layer,
    required this.fact,
    required this.tags,
    this.importance = 0.5,
    required this.createdAt,
    this.lastUsedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'layer': layer,
      'fact': fact,
      'tags': tags,
      'importance': importance,
      'createdAt': createdAt.toIso8601String(),
      'lastUsedAt': lastUsedAt?.toIso8601String(),
    };
  }

  factory KnowledgeEntry.fromMap(String id, Map<String, dynamic> map) {
    return KnowledgeEntry(
      id: id,
      layer: map['layer'] as String? ?? 'general',
      fact: map['fact'] as String? ?? '',
      tags: List<String>.from(map['tags'] as List? ?? const []),
      importance: (map['importance'] as num?)?.toDouble() ?? 0.5,
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'] as String)
          : DateTime.now(),
      lastUsedAt: map['lastUsedAt'] != null
          ? DateTime.parse(map['lastUsedAt'] as String)
          : null,
    );
  }

  KnowledgeEntry copyWith({DateTime? lastUsedAt}) {
    return KnowledgeEntry(
      id: id,
      layer: layer,
      fact: fact,
      tags: tags,
      importance: importance,
      createdAt: createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    );
  }
}

/// The fixed set of layers knowledge gets filed under. Kept as a const
/// list (not a free-form string) so classification always lands on a
/// known collection name rather than silently fragmenting into typo
/// variants ("proffesional" vs "professional") over time.
class KnowledgeLayers {
  static const personal = 'personal';
  static const professional = 'professional';
  static const preferences = 'preferences';
  static const technical = 'technical';
  static const projects = 'projects';
  static const general = 'general';

  static const all = [
    personal,
    professional,
    preferences,
    technical,
    projects,
    general,
  ];
}
