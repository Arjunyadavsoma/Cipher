import '../../chat/services/chat_ai_service.dart';
import '../core/agent_executor.dart';
import '../models/execution_context.dart';
import '../models/execution_result.dart';
import 'context_summarizer_service.dart';

/// The single entrypoint the chat layer calls. ChatProvider should only
/// ever talk to this - it has no knowledge of routing, agents, or tools.
class AgentService {
  AgentService._internal();

  static final AgentService instance = AgentService._internal();

  final _summarizer = ContextSummarizerService.instance;

  Future<AgentExecutionResult> processMessage({
    required String userId,
    required String chatId,
    required String message,
  }) async {
    if (_summarizer.isMemoryTrigger(message)) {
      await _summarizer.saveMemory(userId, message);
    }

    final rollingSummary = await _summarizer.getRollingSummary(userId, chatId);
    final alwaysContext = await _summarizer.buildAlwaysContext(userId);

    final recentMessages = ChatAiService.instance.getRecentMessages(chatId);

    final result = await AgentExecutor.instance.run(
      userId: userId,
      chatId: chatId,
      message: message,
      recentMessages: recentMessages,
      rollingSummary: rollingSummary,
      alwaysContext: alwaysContext,
    );

    // Track this turn locally so the next message has correct recent context.
    ChatAiService.instance.addMessage(
      chatId,
      ConversationMessage(
        role: 'user',
        content: message,
        timestamp: DateTime.now(),
      ),
    );
    ChatAiService.instance.addMessage(
      chatId,
      ConversationMessage(
        role: 'assistant',
        content: result.responseText,
        timestamp: DateTime.now(),
      ),
    );

    await _summarizer.updateSummary(
      userId: userId,
      chatId: chatId,
      previousSummary: rollingSummary,
      userMessage: message,
      assistantResponse: result.responseText,
    );

    return result;
  }
}