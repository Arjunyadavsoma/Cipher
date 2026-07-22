enum AgentActionType {
  sendEmail,
  createCalendarEvent,
  createAutomation,
  sendNotification,
  connectGmail,
  none,
}

/// A structured side-effect an agent wants performed (e.g. actually sending
/// an email, or creating a calendar event) - kept separate from the text
/// response so the UI/executor can decide how to handle it.
class AgentAction {
  final AgentActionType type;
  final Map<String, dynamic> data;

  const AgentAction({required this.type, this.data = const {}});

  Map<String, dynamic> toMap() => {'type': type.name, 'data': data};
}

class Citation {
  final String title;
  final String url;

  const Citation({required this.title, required this.url});

  Map<String, dynamic> toMap() => {'title': title, 'url': url};
}

/// The structured result every agent must return, regardless of what
/// internal pipeline it ran (a single LLM call, or a multi-step research
/// pipeline like the Research Agent).
class AgentExecutionResult {
  final String responseText;
  final String agentName;
  final List<String> usedTools;
  final Duration executionTime;
  final List<Citation> citations;
  final List<String> attachments;
  final AgentAction? action;
  final bool success;
  final String? errorMessage;

  /// Optional per-agent memory patch. AgentExecutor merges this into
  /// the agent's persisted context (Firestore, when contextStorage !=
  /// none) after execute() returns - e.g. DsaHandlers uses this to
  /// carry currentQuestion/hintLevel/interviewActive forward between
  /// turns. Null means "no memory change this turn."
  final Map<String, dynamic>? updatedMemory;

  const AgentExecutionResult({
    required this.responseText,
    required this.agentName,
    this.usedTools = const [],
    this.executionTime = Duration.zero,
    this.citations = const [],
    this.attachments = const [],
    this.action,
    this.success = true,
    this.errorMessage,
    this.updatedMemory,
  });

  factory AgentExecutionResult.failure({
    required String agentName,
    required String errorMessage,
  }) {
    return AgentExecutionResult(
      responseText: "Something went wrong while processing your request.",
      agentName: agentName,
      success: false,
      errorMessage: errorMessage,
    );
  }

  Map<String, dynamic> toLogMap() {
    return {
      'agentName': agentName,
      'usedTools': usedTools,
      'executionTimeMs': executionTime.inMilliseconds,
      'success': success,
      'errorMessage': errorMessage,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
}