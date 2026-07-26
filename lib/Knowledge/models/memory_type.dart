enum MemoryType {
  preference,
  goal,
  identity,
  project,
  decision,
  skill,
  task,
  document,
  conversation,
  code,
  api,
  bug,
  solution,
  fact,
  other;

  static MemoryType fromString(String? type) {
    switch (type?.toLowerCase()) {
      case 'preference': return MemoryType.preference;
      case 'goal': return MemoryType.goal;
      case 'identity': return MemoryType.identity;
      case 'project': return MemoryType.project;
      case 'decision': return MemoryType.decision;
      case 'skill': return MemoryType.skill;
      case 'task': return MemoryType.task;
      case 'document': return MemoryType.document;
      case 'conversation': return MemoryType.conversation;
      case 'code': return MemoryType.code;
      case 'api': return MemoryType.api;
      case 'bug': return MemoryType.bug;
      case 'solution': return MemoryType.solution;
      case 'fact': return MemoryType.fact;
      default: return MemoryType.other;
    }
  }
}