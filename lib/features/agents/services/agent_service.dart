import 'package:cipher_ai/Knowledge/knowledge_retrieval_service.dart';
import 'package:cipher_ai/Knowledge/knowledge_write_service.dart';
import 'package:cipher_ai/Knowledge/query_plan.dart';
import 'package:cipher_ai/Knowledge/query_planner_service.dart';

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
    // ┌─────────────────────────────────────────────────────────┐
    // │ OPTIMIZATION: Run planner, summary, and context fetching │
    // │ ALL AT THE SAME TIME to cut response time in half.       │
    // └─────────────────────────────────────────────────────────┘
    final results = await Future.wait([
      _planner.plan(message),
      _summarizer.getRollingSummary(userId, chatId),
      _summarizer.buildAlwaysContext(userId),
    ]);

    final QueryPlan plan = results[0] as QueryPlan;
    final rollingSummary = results[1] as String;
    final alwaysContext = results[2] as String;

    // ┌─────────────────────────────────────────────────────────┐
    // │ DEBUG PRINTS: Let's see what the planner decided       │
    // └─────────────────────────────────────────────────────────┘
    print('🔎 PLANNER RESULT:');
    print('  - Agent: ${plan.agentName}');
    print('  - Tags: ${plan.requiredKnowledgeTags}');
    print('  - Remember: ${plan.thingsToRemember}');

    // Persist anything new the planner noticed. KnowledgeWriteService
    // now automatically handles overwriting old singular attributes
    // (like jobs) vs appending list items (like projects)!
    final saveFuture = plan.thingsToRemember.isNotEmpty
        ? _knowledgeWrite.saveFacts(userId, plan.thingsToRemember)
        : Future<void>.value();

    final domainContext = await _knowledgeRetrieval.buildDomainContext(
      userId: userId,
      tags: plan.requiredKnowledgeTags,
    );

    // ┌─────────────────────────────────────────────────────────┐
    // │ DEBUG PRINT: Did we actually get context back?         │
    // └─────────────────────────────────────────────────────────┘
    print('📚 KNOWLEDGE CONTEXT INJECTED:');
    print(
      domainContext.isEmpty ? '  (Empty - no tags matched)' : domainContext,
    );

    final recentMessages = ChatAiService.instance.getRecentMessages(chatId);

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

    // Ensure memory saves complete before returning
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
