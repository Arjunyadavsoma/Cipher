/// A single message in the conversation history, kept in a
/// Groq/OpenAI-compatible role/content shape.
class ConversationMessage {
  final String role; // 'user' | 'assistant'
  final String content;
  final DateTime timestamp;

  ConversationMessage({
    required this.role,
    required this.content,
    required this.timestamp,
  });

  Map<String, String> toGroqFormat() => {'role': role, 'content': content};
}

/// Everything an agent needs to execute, passed as a single structured
/// object instead of a bare string. Context is intentionally layered to
/// control token usage:
///
/// - [recentMessages]: last few raw turns, for immediate continuity
/// - [rollingSummary]: compressed history, replaces older raw messages
/// - [alwaysContext]: small, sent on every request regardless of agent
///   (saved memories, core preferences)
/// - [domainContext]: larger, only populated when the selected agent
///   needs topic-specific background (e.g. "education context")
/// - [agentMemory]: per-agent persistent context, loaded only when that
///   specific agent is invoked
class ExecutionContext {
  final String userId;
  final String chatId;
  final String message;

  final List<ConversationMessage> recentMessages;
  final String rollingSummary;

  final String alwaysContext;
  final String domainContext;
  final Map<String, dynamic>? agentMemory;

  final List<String> attachments;
  final String selectedModel;
  final Map<String, dynamic> metadata;

  const ExecutionContext({
    required this.userId,
    required this.chatId,
    required this.message,
    this.recentMessages = const [],
    this.rollingSummary = '',
    this.alwaysContext = '',
    this.domainContext = '',
    this.agentMemory,
    this.attachments = const [],
    this.selectedModel = 'llama-3.3-70b-versatile',
    this.metadata = const {},
  });

  ExecutionContext copyWith({
    String? domainContext,
    Map<String, dynamic>? agentMemory,
  }) {
    return ExecutionContext(
      userId: userId,
      chatId: chatId,
      message: message,
      recentMessages: recentMessages,
      rollingSummary: rollingSummary,
      alwaysContext: alwaysContext,
      domainContext: domainContext ?? this.domainContext,
      agentMemory: agentMemory ?? this.agentMemory,
      attachments: attachments,
      selectedModel: selectedModel,
      metadata: metadata,
    );
  }
}