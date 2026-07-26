/// A single atomic fact stored under a knowledge layer
/// (users/{uid}/knowledge_entries/{entryId}).
class KnowledgeEntry {
  final String id;
  final String layer;
  final String fact;
  final List<String> tags;
  final double importance;
  final DateTime createdAt;
  final DateTime? lastUsedAt;
  
  // NEW FIELDS FOR SCORING
  final int accessCount;
  final DateTime? lastAccessed;
  
  // VECTOR EMBEDDING
  final List<double>? embedding;

  const KnowledgeEntry({
    required this.id,
    required this.layer,
    required this.fact,
    required this.tags,
    this.importance = 0.5,
    required this.createdAt,
    this.lastUsedAt,
    this.accessCount = 0,
    this.lastAccessed,
    this.embedding,
  });

  Map<String, dynamic> toMap() {
    return {
      'layer': layer,
      'fact': fact,
      'tags': tags,
      'importance': importance,
      'createdAt': createdAt.toIso8601String(),
      'lastUsedAt': lastUsedAt?.toIso8601String(),
      'accessCount': accessCount,
      'lastAccessed': lastAccessed?.toIso8601String(),
      if (embedding != null) 'embedding': embedding,
    };
  }

  factory KnowledgeEntry.fromMap(String id, Map<String, dynamic> map) {
    return KnowledgeEntry(
      id: id,
      layer: map['layer'] as String? ?? 'general',
      fact: map['fact'] as String? ?? '',
      tags: List<String>.from(map['tags'] as List? ?? const []),
      importance: (map['importance'] as num?)?.toDouble() ?? 0.5,
      createdAt: map['createdAt'] != null ? DateTime.parse(map['createdAt'] as String) : DateTime.now(),
      lastUsedAt: map['lastUsedAt'] != null ? DateTime.parse(map['lastUsedAt'] as String) : null,
      accessCount: map['accessCount'] as int? ?? 0,
      lastAccessed: map['lastAccessed'] != null ? DateTime.parse(map['lastAccessed'] as String) : null,
      embedding: map['embedding'] != null 
          ? List<double>.from(map['embedding'] as List) 
          : null,
    );
  }

  KnowledgeEntry copyWith({
    String? id,
    DateTime? lastUsedAt,
    DateTime? lastAccessed,
    int? accessCount,
    List<double>? embedding,
  }) {
    return KnowledgeEntry(
      id: id ?? this.id,
      layer: layer,
      fact: fact,
      tags: tags,
      importance: importance,
      createdAt: createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      accessCount: accessCount ?? this.accessCount,
      lastAccessed: lastAccessed ?? this.lastAccessed,
      embedding: embedding ?? this.embedding,
    );
  }
}

/// The fixed set of layers knowledge gets filed under.
class KnowledgeLayers {
  static const personal = 'personal';
  static const professional = 'professional';
  static const technical = 'technical';
  static const projects = 'projects';
  static const education = 'education';
  static const preferences = 'preferences';
  static const schedule = 'schedule';
  static const automations = 'automations';
  static const general = 'general';

  static const all = [
    personal, professional, technical, projects, education, 
    preferences, schedule, automations, general
  ];
}

/// The strict enterprise dictionary.
class KnowledgeTaxonomy {
  static const String currentJob = 'current_job';
  static const String companyName = 'company';
  static const String location = 'location';
  static const String name = 'name';
  static const String timezone = 'timezone';
  static const String primaryEmail = 'primary_email';
  static const String currentFocus = 'current_focus';

  static const String skill = 'skill';
  static const String pastExperience = 'past_experience';
  static const String tool = 'tool';
  
  static const String project = 'project';
  static const String codebase = 'codebase';
  static const String bug = 'bug';
  static const String architecture = 'architecture';

  static const String dsaTopic = 'dsa_topic';
  static const String interviewPrep = 'interview_prep';
  static const String learningResource = 'learning_resource';
  
  static const String diet = 'diet';
  static const String allergy = 'allergy';
  static const String hobby = 'hobby';
  static const String relationship = 'relationship';

  static const String event = 'event';
  static const String routine = 'routine';
  static const String emailRule = 'email_rule';
  static const String script = 'script';

  static const allTags = [
    currentJob, companyName, location, name, timezone, primaryEmail, currentFocus,
    skill, pastExperience, tool, project, codebase, bug, architecture,
    dsaTopic, interviewPrep, learningResource, diet, allergy, hobby, relationship,
    event, routine, emailRule, script
  ];

  static bool isAttribute(String tag) {
    return [
      currentJob, companyName, location, name, timezone, primaryEmail, currentFocus
    ].contains(tag);
  }

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