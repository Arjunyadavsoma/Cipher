import 'package:cipher_ai/features/agents/DSA_agent/dsa_handlers.dart';
import 'package:cipher_ai/features/agents/DSA_agent/dsa_intent_parser.dart';
import 'package:cipher_ai/features/agents/DSA_agent/dsa_question.dart';
import 'package:cipher_ai/features/agents/DSA_agent/dsa_respository.dart';
import 'package:cipher_ai/features/agents/DSA_agent/gfg_fetch_service.dart';
import 'package:cipher_ai/features/agents/core/base_agent.dart';
import 'package:cipher_ai/features/agents/core/tool_manager.dart';
import 'package:cipher_ai/features/agents/models/agent_context_storage.dart';
import 'package:cipher_ai/features/agents/models/execution_context.dart';
import 'package:cipher_ai/features/agents/models/execution_result.dart';

class DsaAgent implements BaseAgent {
  @override
  String get id => 'dsa_agent';

  @override
  String get name => 'DSA Agent';

  @override
  String get description =>
      'Helps users practice, understand, solve, and revise coding interview problems. '
      'Fetches GeeksforGeeks Problem of the Day, gives progressive hints, reviews code, '
      'and tracks learning progress.';

  @override
  List<String> get tools => const ['groq', 'firebase', 'http', 'notification'];

  @override
  AgentContextStorage get contextStorage => AgentContextStorage.firestore;

  final DsaIntentParser _intentParser;
  final DsaHandlers _handlers;

  // Fixed: previously constructed FirebaseDsaRepository() and
  // GfgFetchService() twice - once into unused fields (_repository,
  // _gfgService), once into _handlers. Built once now and passed
  // through, matching what the analyzer's unused_field warnings flagged.
  DsaAgent()
    : _intentParser = DsaIntentParser(),
      _handlers = DsaHandlers(
        FirebaseDsaRepository(),
        GfgFetchService(),
        ToolManager.instance,
      );

  @override
  String get systemPrompt => DsaIntentParser.systemPrompt;

  @override
  Future<AgentExecutionResult> execute(ExecutionContext context) async {
    try {
      final history = context.recentMessages
          .map((m) => m.toGroqFormat())
          .toList();
      final parsed = await _intentParser.parseIntent(context.message, history);

      final intent = parsed['intent'] as String? ?? 'other';
      final memory = context.agentMemory ?? {};

      final currentQuestion = memory['currentQuestion'] != null
          ? DsaQuestion.fromMap(
              Map<String, dynamic>.from(memory['currentQuestion']),
            )
          : null;
      final hintLevel = memory['hintLevel'] as int? ?? 0;
      final interviewActive = memory['interviewActive'] as bool? ?? false;

      switch (intent) {
        case 'get_potd':
          return _handlers.handleGetPotd(context, currentQuestion);
        case 'explain':
          return _handlers.handleExplain(context, currentQuestion);
        case 'hint':
          return _handlers.handleHint(context, currentQuestion, hintLevel);
        case 'reveal_solution':
          return _handlers.handleRevealSolution(
            context,
            currentQuestion,
            parsed,
          );
        case 'review_code':
          return _handlers.handleReviewCode(context, currentQuestion, parsed);
        case 'complexity':
          return _handlers.handleComplexity(context, currentQuestion, parsed);
        case 'dry_run':
          return _handlers.handleDryRun(context, currentQuestion, parsed);
        case 'save':
          return _handlers.handleSave(context, currentQuestion);
        case 'list_saved':
          return _handlers.handleListSaved(context);
        case 'revise':
          return _handlers.handleRevise(context);
        case 'interview_mode':
          return _handlers.handleInterviewMode(
            context,
            currentQuestion,
            interviewActive,
          );
        default:
          return AgentExecutionResult(
            responseText:
                "I'm the DSA Agent. I can fetch today's problem, give hints, "
                "review code, and run mock interviews. What would you like to do?",
            agentName: name,
          );
      }
    } catch (e, st) {
      // ignore: avoid_print
      print('DsaAgent.execute failed: $e\n$st');
      return AgentExecutionResult(
        responseText:
            "I encountered an error processing your DSA request. Please try again.",
        agentName: name,
        success: false,
        errorMessage: '$e\n$st',
        usedTools: const ['groq', 'firebase'],
      );
    }
  }
}
