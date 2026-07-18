import 'package:mimir_ai/features/agents/research_agent/research_agent.dart';

import '../built_in/email_agent.dart';
import '../models/agent_context_storage.dart';
import '../models/execution_context.dart';
import '../models/execution_result.dart';
import '../repositories/agent_memory_repository.dart';
import '../repositories/agent_repository.dart';
import 'agent_registry.dart';
import 'agent_router.dart';
import 'base_agent.dart';

/// The final step before an agent actually runs. Builds the full
/// ExecutionContext (loading per-agent memory only if that agent needs
/// it), executes the agent, and logs the result.
///
/// Resolution priority, highest to lowest:
///   1. Sticky state - a pending email draft, a pending inbox search
///      follow-up, or a research continuation. Live conversational
///      state beats any single-message classification.
///   2. Explicit @mention - the user typed "@video" or similar. A
///      deterministic, user-stated override; no LLM call should be
///      able to beat it.
///   3. QueryPlannerService's pre-routed agent, if its confidence
///      clears the threshold. Replaces the old
///      IntentGate -> IntentClassifier -> AgentRouter.route() chain -
///      AgentService now runs that single planning call itself and
///      passes the result in via [preRoutedAgentName]/
///      [preRoutedConfidence].
///   4. Default Chat Agent, as the final fallback.
class AgentExecutor {
  AgentExecutor._internal();

  static final AgentExecutor instance = AgentExecutor._internal();

  static const double _confidenceThreshold = 0.80;

  Future<AgentExecutionResult> run({
    required String userId,
    required String chatId,
    required String message,
    required List<ConversationMessage> recentMessages,
    required String rollingSummary,
    required String alwaysContext,
    String domainContext = '',
    String? preRoutedAgentName,
    double preRoutedConfidence = 0.0,
  }) async {
    final stopwatch = Stopwatch()..start();

    BaseAgent agent;
    Map<String, dynamic>? agentMemory;

    final emailAgent = AgentRegistry.instance.getAgent('email_agent');
    Map<String, dynamic>? emailAgentMemory;
    if (emailAgent != null &&
        emailAgent.contextStorage != AgentContextStorage.none) {
      emailAgentMemory = await AgentMemoryRepository.instance.loadAgentContext(
        userId: userId,
        agentId: emailAgent.id,
        storage: emailAgent.contextStorage,
      );
    }

    final hasPendingDraft = emailAgentMemory?['pendingDraft'] != null;
    final hasPendingSearch = emailAgentMemory?['pendingSearchResults'] != null;
    final looksLikeSearchFollowUp =
        hasPendingSearch && EmailAgent.looksLikeSearchFollowUp(message);

    final researchAgent = AgentRegistry.instance.getAgent('research_agent');
    Map<String, dynamic>? researchAgentMemory;
    if (researchAgent != null &&
        researchAgent.contextStorage != AgentContextStorage.none) {
      researchAgentMemory = await AgentMemoryRepository.instance.loadAgentContext(
        userId: userId,
        agentId: researchAgent.id,
        storage: researchAgent.contextStorage,
      );
    }

    final hasLastPaper = researchAgentMemory?['lastPaper'] != null;
    final looksLikeResearchContinuation =
        hasLastPaper && ResearchAgent.looksLikeContinuation(message);

    if (emailAgent != null && (hasPendingDraft || looksLikeSearchFollowUp)) {
      // ignore: avoid_print
      print('AgentExecutor: sticky ${hasPendingDraft ? "pending draft" : "search follow-up"} -> ${emailAgent.name}');
      agent = emailAgent;
      agentMemory = emailAgentMemory;
    } else if (researchAgent != null && looksLikeResearchContinuation) {
      // ignore: avoid_print
      print('AgentExecutor: sticky research continuation -> ${researchAgent.name}');
      agent = researchAgent;
      agentMemory = researchAgentMemory;
    } else {
      // Explicit @mention beats the planner's pick outright - same
      // precedence the old AgentRouter.route() enforced (mention was
      // checked as Step 1, before IntentGate/IntentClassifier ran at
      // all).
      final mentioned = AgentRouter.instance.findMentionedAgent(message);
      if (mentioned != null) {
        // ignore: avoid_print
        print('AgentExecutor: @mention -> ${mentioned.name}');
      }

      BaseAgent? resolved = mentioned;

      if (resolved == null &&
          preRoutedAgentName != null &&
          preRoutedConfidence >= _confidenceThreshold) {
        resolved = AgentRegistry.instance.findByName(preRoutedAgentName);
        if (resolved != null) {
          // ignore: avoid_print
          print('AgentExecutor: planner picked "${resolved.name}" '
              'at confidence $preRoutedConfidence');
        }
      }

      agent = resolved ?? AgentRegistry.instance.defaultAgent;

      if (agent.id == emailAgent?.id) {
        // Already loaded above - avoid a redundant Firestore read.
        agentMemory = emailAgentMemory;
      } else if (agent.id == researchAgent?.id) {
        // Already loaded above - avoid a redundant Firestore read.
        agentMemory = researchAgentMemory;
      } else if (agent.contextStorage != AgentContextStorage.none) {
        agentMemory = await AgentMemoryRepository.instance.loadAgentContext(
          userId: userId,
          agentId: agent.id,
          storage: agent.contextStorage,
        );
      }
    }

    final context = ExecutionContext(
      userId: userId,
      chatId: chatId,
      message: message,
      recentMessages: recentMessages,
      rollingSummary: rollingSummary,
      alwaysContext: alwaysContext,
      domainContext: domainContext,
      agentMemory: agentMemory,
    );

    AgentExecutionResult result;
    try {
      result = await agent.execute(context);
    } catch (e) {
      print('AgentExecutor: agent.execute() threw: $e');
      result = AgentExecutionResult.failure(
        agentName: agent.name,
        errorMessage: e.toString(),
      );
    }

    stopwatch.stop();

    await AgentRepository.instance.logExecution(
      userId: userId,
      agentName: agent.name,
      message: message,
      response: result.responseText,
      toolsUsed: result.usedTools,
      duration: stopwatch.elapsed,
    );

    await AgentRepository.instance.incrementExecutionCount(userId, agent.id);

    return result;
  }
}