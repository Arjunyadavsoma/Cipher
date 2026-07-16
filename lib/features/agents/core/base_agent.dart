import '../models/agent_context_storage.dart';
import '../models/execution_context.dart';
import '../models/execution_result.dart';

/// Every agent must implement this interface. Adding a new agent only
/// requires creating a new class here and registering it in
/// [AgentRegistry] - no changes to the router, executor, or chat UI.
abstract class BaseAgent {
  String get id;

  String get name;

  String get description;

  String get systemPrompt;

  List<String> get tools;

  /// Where this agent's persistent context lives, if any. Defaults to
  /// [AgentContextStorage.none] for agents that don't need memory beyond
  /// the conversation itself.
  AgentContextStorage get contextStorage => AgentContextStorage.none;

  Future<AgentExecutionResult> execute(ExecutionContext context);
}