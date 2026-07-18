import 'package:mimir_ai/features/agents/DSA_agent/dsa_question.dart';
import 'package:mimir_ai/features/agents/DSA_agent/dsa_respository.dart';
import 'package:mimir_ai/features/agents/DSA_agent/gfg_fetch_service.dart';
import 'package:mimir_ai/features/agents/DSA_agent/notification_service.dart';
import 'package:mimir_ai/features/agents/core/base_agent.dart';
import 'package:mimir_ai/features/agents/core/tool_manager.dart';
import 'package:mimir_ai/features/agents/models/agent_context_storage.dart';
import 'package:mimir_ai/features/agents/models/execution_context.dart';
import 'package:mimir_ai/features/agents/models/execution_result.dart';

import 'dsa_handlers.dart';
import 'dsa_intent_parser.dart';

/// Production-grade DSA (Data Structures & Algorithms) Agent.
///
/// Acts as an intelligent learning assistant that helps users practice,
/// understand, solve, save, and revise coding interview problems.
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

  final DsaRepository _repository;
  final GfgFetchService _gfgService;
  final DsaIntentParser _intentParser;
  final DsaHandlers _handlers;

  DsaAgent()
      : _repository = FirebaseDsaRepository(),
        _gfgService = GfgFetchService(),
        _intentParser = DsaIntentParser(),
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
      final history = context.recentMessages.map((m) => m.toGroqFormat()).toList();
      final parsed = await _intentParser.parseIntent(context.message, history);

      final intent = parsed['intent'] as String? ?? 'other';
      final memory = context.agentMemory ?? {};

      // Load Sticky State
      final currentQuestion = memory['currentQuestion'] != null
          ? DsaQuestion.fromMap(Map<String, dynamic>.from(memory['currentQuestion']))
          : null;
      final hintLevel = memory['hintLevel'] as int? ?? 0;
      final interviewActive = memory['interviewActive'] as bool? ?? false;

      // NOTE: previously only 4 of the 11 intents DsaHandlers actually
      // implements were routed here (get_potd, hint, reveal_solution,
      // review_code) - every other request (explain/complexity/
      // dry_run/save/list_saved/revise/interview_mode) fell through to
      // the generic "What would you like to do?" message even when
      // classification worked correctly. All cases restored below,
      // matching the handler methods that already exist in
      // dsa_handlers.dart.
      switch (intent) {
        case 'get_potd':
          return _handlers.handleGetPotd(context, currentQuestion);
        case 'explain':
          return _handlers.handleExplain(context, currentQuestion);
        case 'hint':
          return _handlers.handleHint(context, currentQuestion, hintLevel);
        case 'reveal_solution':
          return _handlers.handleRevealSolution(context, currentQuestion, parsed);
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
          return _handlers.handleInterviewMode(context, currentQuestion, interviewActive);
        default:
          return AgentExecutionResult(
            responseText: "I am the DSA Agent. I can fetch today's problem, give hints, review code, and help you prepare for interviews. What would you like to do?",
            agentName: name,
          );
      }
    } catch (e, st) {
      return AgentExecutionResult(
        responseText: "I encountered an error processing your DSA request. Please try again.",
        agentName: name,
        success: false,
        errorMessage: '$e\n$st',
        usedTools: const ['groq', 'firebase'],
      );
    }
  }
}