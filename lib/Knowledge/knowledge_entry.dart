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

  KnowledgeEntry copyWith({
    String? id,
    DateTime? lastUsedAt,
  }) {
    return KnowledgeEntry(
      id: id ?? this.id,
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
/// The fixed set of layers knowledge gets filed under.
class KnowledgeLayers {
  static const personal = 'personal';
  static const professional = 'professional';
  static const technical = 'technical';
  static const projects = 'projects';
  static const education = 'education'; // For DSA, interview prep, courses
  static const preferences = 'preferences';
  static const schedule = 'schedule'; // For events, meetings, automations
  static const automations = 'automations'; // For email rules, scripts
  static const general = 'general';

  static const all = [
    personal, professional, technical, projects, education, 
    preferences, schedule, automations, general
  ];
}

/// The strict enterprise dictionary.
/// The LLM MUST choose from these tags. Dart enforces the layer and behavior.
class KnowledgeTaxonomy {
  // ─── SINGULAR ATTRIBUTES (Overwrites old facts) ─────────────────────
  static const String currentJob = 'current_job';
  static const String companyName = 'company';
  static const String location = 'location';
  static const String name = 'name';
  static const String timezone = 'timezone';
  static const String primaryEmail = 'primary_email';
  static const String currentFocus = 'current_focus'; // e.g., "preparing for interviews"

  // ─── LIST ITEMS (Appends new facts) ─────────────────────────────────
  // Professional & Technical
  static const String skill = 'skill';
  static const String pastExperience = 'past_experience';
  static const String tool = 'tool'; // VS Code, Postman, Docker
  
  // Projects & Code
  static const String project = 'project';
  static const String codebase = 'codebase'; // specific repo info
  static const String bug = 'bug';
  static const String architecture = 'architecture';

  // Education & Prep (DSA, Interviews)
  static const String dsaTopic = 'dsa_topic'; // e.g., graphs, dynamic programming
  static const String interviewPrep = 'interview_prep';
  static const String learningResource = 'learning_resource'; // links, books
  
  // Preferences & Personal
  static const String diet = 'diet';
  static const String allergy = 'allergy';
  static const String hobby = 'hobby';
  static const String relationship = 'relationship';

  // Schedule & Automations
  static const String event = 'event'; // meetings, birthdays
  static const String routine = 'routine'; // "every monday I do X"
  static const String emailRule = 'email_rule'; // "forward stripe emails to Raj"
  static const String script = 'script'; // "run build script at 5pm"

  static const allTags = [
    currentJob, companyName, location, name, timezone, primaryEmail, currentFocus,
    skill, pastExperience, tool, project, codebase, bug, architecture,
    dsaTopic, interviewPrep, learningResource, diet, allergy, hobby, relationship,
    event, routine, emailRule, script
  ];

  /// Returns true if this tag represents a singular attribute (should overwrite)
  static bool isAttribute(String tag) {
    return [
      currentJob, companyName, location, name, timezone, primaryEmail, currentFocus
    ].contains(tag);
  }

  /// Deterministically maps a tag to its Firestore collection layer
  static String layerForTag(String tag) {
    if ([currentJob, companyName, pastExperience].contains(tag)) return KnowledgeLayers.professional;
    if ([skill, tool, codebase, bug, architecture].contains(tag)) return KnowledgeLayers.technical;
    if ([project].contains(tag)) return KnowledgeLayers.projects;
    if ([dsaTopic, interviewPrep, learningResource].contains(tag)) return KnowledgeLayers.education;
    if ([diet, allergy, hobby].contains(tag)) return KnowledgeLayers.preferences;
    if ([name, location, timezone, relationship].contains(tag)) return KnowledgeLayers.personal;
    if ([primaryEmail, emailRule].contains(tag)) return KnowledgeLayers.automations;
    if ([event, routine, script, currentFocus].contains(tag)) return KnowledgeLayers.schedule;
    return KnowledgeLayers.general;
  }
}