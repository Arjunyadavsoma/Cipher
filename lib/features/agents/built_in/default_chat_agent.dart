import '../core/base_agent.dart';
import '../core/tool_manager.dart';
import '../models/agent_context_storage.dart';
import '../models/execution_context.dart';
import '../models/execution_result.dart';

class DefaultChatAgent implements BaseAgent {
  @override
  String get id => 'default_chat';

  @override
  String get name => 'Default Chat Agent';

  @override
  String get description =>
      'Handles general conversation, casual questions, and anything that '
      'does not require a specialized agent.';

  @override
  String get systemPrompt =>
      'You are Mimir AI, a helpful personal AI assistant.';

  @override
  List<String> get tools => ['groq'];

  @override
  AgentContextStorage get contextStorage => AgentContextStorage.none;

  @override
  Future<AgentExecutionResult> execute(ExecutionContext context) async {
    final history =
        context.recentMessages.map((m) => m.toGroqFormat()).toList();

    final response = await ToolManager.instance.executeTool('groq', {
      'systemPrompt': systemPrompt,
      'message': _buildPrompt(context),
      'history': history,
    });

    return AgentExecutionResult(
      responseText: response as String,
      agentName: name,
      usedTools: const ['groq'],
    );
  }

  String _buildPrompt(ExecutionContext context) {
    final buffer = StringBuffer();
    if (context.alwaysContext.isNotEmpty) {
      buffer.writeln(context.alwaysContext);
      buffer.writeln();
    }
    // Knowledge-retrieval context (KnowledgeRetrievalService.buildDomainContext,
    // routed here by AgentService via QueryPlannerService.requiredKnowledgeTags).
    // This was previously built but never read by this agent, so retrieved
    // facts never reached the model even when retrieval succeeded.
    if (context.domainContext.isNotEmpty) {
      buffer.writeln(context.domainContext);
      buffer.writeln();
    }
    if (context.rollingSummary.isNotEmpty) {
      buffer.writeln("Conversation so far: ${context.rollingSummary}");
      buffer.writeln();
    }
    buffer.write(context.message);
    return buffer.toString();
  }
}