import 'package:flutter/foundation.dart';
import 'package:cipher_ai/Knowledge/knowledge_retrieval_service.dart';
import 'package:cipher_ai/Knowledge/knowledge_write_service.dart';
import 'package:cipher_ai/Knowledge/query_plan.dart';
import 'package:cipher_ai/Knowledge/query_planner_service.dart';
import 'package:cipher_ai/features/agents/core/agent_router.dart';

import '../../chat/services/chat_ai_service.dart';
import '../core/agent_executor.dart';
import '../models/execution_context.dart';
import '../models/execution_result.dart';
import 'context_summarizer_service.dart';

/// The single entrypoint the chat layer calls.
class AgentService {
  AgentService._internal();
  static final AgentService instance = AgentService._internal();

  final _summarizer = ContextSummarizerService.instance;
  final _planner = QueryPlannerService.instance;
  final _router = AgentRouter.instance;

  final _knowledgeRetrieval = KnowledgeRetrievalService.instance;
  final _knowledgeWrite = KnowledgeWriteService.instance;

  Future<AgentExecutionResult> processMessage({
    required String userId,
    required String chatId,
    required String message,
  }) async {
    // ┌─────────────────────────────────────────────────────────┐
    // │ 1. @MENTION OVERRIDES: Check for explicit commands first │
    // └─────────────────────────────────────────────────────────┘
    final mentionedAgent = _router.findMentionedAgent(message);
    final bool hasMention = mentionedAgent != null;

    // ┌─────────────────────────────────────────────────────────┐
    // │ 2. FETCH CONTEXT FIRST: Get history and summary          │
    // └─────────────────────────────────────────────────────────┘
    // FIX: Changed to Future.wait<dynamic> to allow mixed return types
    final contextResults = await Future.wait<dynamic>([
      _summarizer.getRollingSummary(userId, chatId),
      _summarizer.buildAlwaysContext(userId),
      Future.value(ChatAiService.instance.getRecentMessages(chatId)),
    ]);

    final rollingSummary = contextResults[0] as String;
    final alwaysContext = contextResults[1] as String;
    final recentMessages = contextResults[2] as List<ConversationMessage>;

    // ┌─────────────────────────────────────────────────────────┐
    // │ 3. PLANNER EXECUTION: Run planner with FULL CONTEXT      │
    // └─────────────────────────────────────────────────────────┘
    QueryPlan? plan;
    if (!hasMention) {
      plan = await _planner.plan(
        message: message,
        rollingSummary: rollingSummary,
        recentMessages: recentMessages,
      );
    }

    // Determine routing and memory actions
    final String agentName = hasMention 
        ? mentionedAgent.name 
        : (plan?.agentName ?? 'Default Chat Agent');
        
    final double confidence = hasMention ? 1.0 : (plan?.confidence ?? 0.5);
    final String cleanedQuery = hasMention 
        ? message 
        : (plan?.cleanedQuery.isNotEmpty == true ? plan!.cleanedQuery : message);
        
    final List<String> thingsToRemember = hasMention ? [] : (plan?.thingsToRemember ?? []);

    debugPrint('🔎 ROUTING DECISION:');
    debugPrint('  - Agent: $agentName');
    debugPrint('  - Triggered by @mention: $hasMention');

    // ┌─────────────────────────────────────────────────────────┐
    // │ 4. RAG KNOWLEDGE RETRIEVAL: Vector search on raw message │
    // └─────────────────────────────────────────────────────────┘
    final saveFuture = thingsToRemember.isNotEmpty
        ? _knowledgeWrite.saveFacts(userId, thingsToRemember)
        : Future<void>.value();

    final domainContext = await _knowledgeRetrieval.buildDomainContext(
      userId: userId,
      userQuery: message,
    );

    debugPrint('📚 KNOWLEDGE CONTEXT INJECTED:');
    debugPrint(domainContext.isEmpty ? '  (Empty - no relevant facts found)' : domainContext);

    // ┌─────────────────────────────────────────────────────────┐
    // │ 5. EXECUTE AGENT                                         │
    // └─────────────────────────────────────────────────────────┘
    final result = await AgentExecutor.instance.run(
      userId: userId,
      chatId: chatId,
      message: cleanedQuery,
      recentMessages: recentMessages,
      rollingSummary: rollingSummary,
      alwaysContext: alwaysContext,
      domainContext: domainContext,
      preRoutedAgentName: agentName,
      preRoutedConfidence: confidence,
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