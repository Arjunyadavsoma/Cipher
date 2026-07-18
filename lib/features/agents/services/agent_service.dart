import 'package:mimir_ai/Knowledge/knowledge_retrieval_service.dart';
import 'package:mimir_ai/Knowledge/knowledge_write_service.dart';
import 'package:mimir_ai/Knowledge/query_plan.dart';
import 'package:mimir_ai/Knowledge/query_planner_service.dart';

import '../../chat/services/chat_ai_service.dart';
import '../core/agent_executor.dart';
import '../models/execution_context.dart';
import '../models/execution_result.dart';
import 'context_summarizer_service.dart';

/// The single entrypoint the chat layer calls. Unchanged contract from
/// before - ChatProvider still only ever talks to this.
///
/// NEW: runs QueryPlannerService once per message (replacing the old
/// IntentGate -> IntentClassifier -> AgentRouter chain's two calls with
/// one), then uses the plan's requiredKnowledgeTags to pull relevant
/// KnowledgeEntry facts into ExecutionContext.domainContext, and saves
/// any thingsToRemember the planner surfaced.
class AgentService {
  AgentService._internal();

  static final AgentService instance = AgentService._internal();

  final _summarizer = ContextSummarizerService.instance;
  final _planner = QueryPlannerService.instance;
  final _knowledgeRetrieval = KnowledgeRetrievalService.instance;
  final _knowledgeWrite = KnowledgeWriteService.instance;

  Future<AgentExecutionResult> processMessage({
    required String userId,
    required String chatId,
    required String message,
  }) async {
    // Existing "remember that..." keyword trigger stays as-is - it's a
    // cheap, explicit, user-initiated path and doesn't need to wait on
    // the planner call below.
    if (_summarizer.isMemoryTrigger(message)) {
      await _summarizer.saveMemory(userId, message);
    }

    final rollingSummary = await _summarizer.getRollingSummary(userId, chatId);
    final alwaysContext = await _summarizer.buildAlwaysContext(userId);
    final recentMessages = ChatAiService.instance.getRecentMessages(chatId);

    // Single planning call: agent routing + knowledge tags + new facts,
    // in one JSON response instead of two separate Groq calls.
    final QueryPlan plan = await _planner.plan(message);

    // Persist anything new the planner noticed. Non-blocking relative
    // to building domainContext below - both can proceed, but we don't
    // want a slow knowledge write to delay the response, so this isn't
    // awaited inline with retrieval.
    final saveFuture = plan.thingsToRemember.isNotEmpty
        ? _knowledgeWrite.saveFacts(userId, plan.thingsToRemember)
        : Future<void>.value();

    final domainContext = await _knowledgeRetrieval.buildDomainContext(
      userId: userId,
      tags: plan.requiredKnowledgeTags,
    );

    final result = await AgentExecutor.instance.run(
      userId: userId,
      chatId: chatId,
      message: plan.cleanedQuery.isNotEmpty ? plan.cleanedQuery : message,
      recentMessages: recentMessages,
      rollingSummary: rollingSummary,
      alwaysContext: alwaysContext,
      domainContext: domainContext,
      preRoutedAgentName: plan.agentName,
      preRoutedConfidence: plan.confidence,
    );

    await saveFuture;

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
