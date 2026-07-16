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
/// it), executes the agent, and logs the result - all in one place so
/// AgentService/ChatProvider don't need to know any of these details.
class AgentExecutor {
  AgentExecutor._internal();

  static final AgentExecutor instance = AgentExecutor._internal();

  Future<AgentExecutionResult> run({
    required String userId,
    required String chatId,
    required String message,
    required List<ConversationMessage> recentMessages,
    required String rollingSummary,
    required String alwaysContext,
  }) async {
    final stopwatch = Stopwatch()..start();

    // Sticky-agent check: a short confirmation like "send it" - or a short
    // reference like "the first one" / "find more on that" - has no context
    // of its own for IntentGate/IntentClassifier to work with, and can
    // easily be misrouted to the Default Chat Agent. If an agent has
    // pending state (a draft, search results, an analyzed paper) and this
    // message reads as a reference back to it, keep routing to that agent
    // for this turn rather than asking the classifier to guess - the
    // agent's own execute() logic still decides what the message actually
    // means.
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
      final decision = await AgentRouter.instance.route(message);
      agent = decision.agent;

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