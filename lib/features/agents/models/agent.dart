import 'agent_context_storage.dart';

enum AgentCategory { general, coding, research, email, calendar ,news,}

enum AgentStatus { active, disabled, maintenance }

/// Static configuration/metadata for an agent. This is distinct from
/// [BaseAgent] (the executable interface) - this model is what gets
/// persisted to Firestore and displayed in any agent-management UI.
class Agent {
  final String id;
  final String name;
  final String description;
  final AgentCategory category;
  final String systemPrompt;
  final List<String> availableTools;
  final AgentStatus status;
  final bool enabled;
  final AgentContextStorage contextStorage;
  final DateTime createdAt;
  final DateTime? lastUsedAt;
  final int executionCount;

  const Agent({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.systemPrompt,
    required this.availableTools,
    this.status = AgentStatus.active,
    this.enabled = true,
    this.contextStorage = AgentContextStorage.none,
    required this.createdAt,
    this.lastUsedAt,
    this.executionCount = 0,
  });

  Agent copyWith({
    AgentStatus? status,
    bool? enabled,
    DateTime? lastUsedAt,
    int? executionCount,
  }) {
    return Agent(
      id: id,
      name: name,
      description: description,
      category: category,
      systemPrompt: systemPrompt,
      availableTools: availableTools,
      status: status ?? this.status,
      enabled: enabled ?? this.enabled,
      contextStorage: contextStorage,
      createdAt: createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      executionCount: executionCount ?? this.executionCount,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'category': category.name,
      'systemPrompt': systemPrompt,
      'availableTools': availableTools,
      'status': status.name,
      'enabled': enabled,
      'contextStorage': contextStorage.name,
      'createdAt': createdAt.toIso8601String(),
      'lastUsedAt': lastUsedAt?.toIso8601String(),
      'executionCount': executionCount,
    };
  }

  factory Agent.fromMap(Map<String, dynamic> map) {
    return Agent(
      id: map['id'],
      name: map['name'],
      description: map['description'],
      category: AgentCategory.values.firstWhere(
        (c) => c.name == map['category'],
        orElse: () => AgentCategory.general,
      ),
      systemPrompt: map['systemPrompt'],
      availableTools: List<String>.from(map['availableTools'] ?? []),
      status: AgentStatus.values.firstWhere(
        (s) => s.name == map['status'],
        orElse: () => AgentStatus.active,
      ),
      enabled: map['enabled'] ?? true,
      contextStorage: AgentContextStorage.values.firstWhere(
        (s) => s.name == map['contextStorage'],
        orElse: () => AgentContextStorage.none,
      ),
      createdAt: DateTime.parse(map['createdAt']),
      lastUsedAt: map['lastUsedAt'] != null ? DateTime.parse(map['lastUsedAt']) : null,
      executionCount: map['executionCount'] ?? 0,
    );
  }
}