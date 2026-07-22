import 'package:cipher_ai/features/agents/DSA_agent/dsa_question.dart';
import 'package:cipher_ai/features/agents/DSA_agent/dsa_respository.dart';
import 'package:cipher_ai/features/agents/DSA_agent/gfg_fetch_service.dart';
import 'package:cipher_ai/features/agents/core/tool_manager.dart';
import 'package:cipher_ai/features/agents/models/execution_context.dart';
import 'package:cipher_ai/features/agents/models/execution_result.dart';

/// Implements every intent DsaIntentParser can classify. Kept separate
/// from DsaAgent so agent.execute() stays a thin router - each handler
/// here owns one conversational responsibility (fetch POTD, give a
/// hint, review code, etc).
///
/// ASSUMPTION: AgentExecutionResult supports an optional `updatedMemory`
/// map that AgentExecutor persists back to Firestore after execute()
/// returns - the same sticky-state pattern EmailAgent/ResearchAgent use
/// for pendingDraft/lastPaper. If your ExecutionResult model uses a
/// different field name, rename `updatedMemory` below to match.
class DsaHandlers {
  final DsaRepository _repo;
  final GfgFetchService _gfg;
  final ToolManager _toolManager;

  DsaHandlers(this._repo, this._gfg, this._toolManager);

  Future<AgentExecutionResult> handleGetPotd(
    ExecutionContext context,
    DsaQuestion? currentQuestion,
  ) async {
    try {
      var question = await _repo.getTodaysQuestion();

      if (question == null) {
        question = await _gfg.fetchProblemOfTheDay();
        await _repo.cacheDailyQuestion(question);
      }

      return AgentExecutionResult(
        responseText:
            "**Today's Problem: ${question.title}** (${question.difficulty})\n\n"
            "${question.description}\n\n"
            "Want a hint, or should I explain the approach?",
        agentName: 'DSA Agent',
        usedTools: const ['firebase', 'http'],
        updatedMemory: {'currentQuestion': question.toMap(), 'hintLevel': 0},
      );
    } catch (e) {
      return AgentExecutionResult(
        responseText:
            "I couldn't fetch today's problem right now (${e.toString()}). "
            "GeeksforGeeks may be temporarily blocking requests - try again shortly.",
        agentName: 'DSA Agent',
        success: false,
      );
    }
  }

  Future<AgentExecutionResult> handleExplain(
    ExecutionContext context,
    DsaQuestion? currentQuestion,
  ) async {
    if (currentQuestion == null) return _noActiveQuestion();

    final response = await _toolManager.executeTool('groq', {
      'systemPrompt':
          'You are a patient DSA tutor. Explain the approach '
          'to solve this problem clearly, in plain language, without '
          'giving away the full code unless asked.',
      'message':
          'Problem: ${currentQuestion.title}\n\n'
          '${currentQuestion.description}\n\n'
          'Explain how to approach this problem.',
    });

    return AgentExecutionResult(
      responseText: response as String,
      agentName: 'DSA Agent',
      usedTools: const ['groq'],
    );
  }

  Future<AgentExecutionResult> handleHint(
    ExecutionContext context,
    DsaQuestion? currentQuestion,
    int hintLevel,
  ) async {
    if (currentQuestion == null) return _noActiveQuestion();

    // Progressive hints: level 0 = nudge, level 1 = approach, level 2+ = near-solution.
    final hintPrompt = switch (hintLevel) {
      0 =>
        'Give a very small nudge - just point at the right data structure or pattern, nothing more.',
      1 =>
        'Give a more concrete hint about the approach, but do not write code.',
      _ =>
        'Give a strong hint close to the solution approach, still no full code.',
    };

    final response = await _toolManager.executeTool('groq', {
      'systemPrompt':
          'You are a DSA tutor giving progressive hints. $hintPrompt',
      'message':
          'Problem: ${currentQuestion.title}\n\n${currentQuestion.description}',
    });

    return AgentExecutionResult(
      responseText: response as String,
      agentName: 'DSA Agent',
      usedTools: const ['groq'],
      updatedMemory: {
        'currentQuestion': currentQuestion.toMap(),
        'hintLevel': hintLevel + 1,
      },
    );
  }

  Future<AgentExecutionResult> handleRevealSolution(
    ExecutionContext context,
    DsaQuestion? currentQuestion,
    Map<String, dynamic> parsed,
  ) async {
    if (currentQuestion == null) return _noActiveQuestion();

    final language = parsed['language'] as String? ?? 'Python';
    final response = await _toolManager.executeTool('groq', {
      'systemPrompt':
          'You are a DSA tutor. Provide a clean, well-commented '
          'solution in $language, followed by a brief explanation of the approach.',
      'message':
          'Problem: ${currentQuestion.title}\n\n${currentQuestion.description}',
    });

    return AgentExecutionResult(
      responseText: response as String,
      agentName: 'DSA Agent',
      usedTools: const ['groq'],
    );
  }

  Future<AgentExecutionResult> handleReviewCode(
    ExecutionContext context,
    DsaQuestion? currentQuestion,
    Map<String, dynamic> parsed,
  ) async {
    final code = parsed['code'] as String? ?? '';
    if (code.trim().isEmpty) {
      return AgentExecutionResult(
        responseText:
            "I don't see any code to review - paste your solution and I'll take a look.",
        agentName: 'DSA Agent',
      );
    }

    final response = await _toolManager.executeTool('groq', {
      'systemPrompt':
          'You are a senior engineer reviewing DSA interview code. '
          'Check correctness, edge cases, time/space complexity, and style. Be direct and specific.',
      'message':
          'Problem context: ${currentQuestion?.title ?? "not specified"}\n\n'
          'Code:\n```${parsed['language'] ?? ''}\n$code\n```',
    });

    return AgentExecutionResult(
      responseText: response as String,
      agentName: 'DSA Agent',
      usedTools: const ['groq'],
    );
  }

  Future<AgentExecutionResult> handleComplexity(
    ExecutionContext context,
    DsaQuestion? currentQuestion,
    Map<String, dynamic> parsed,
  ) async {
    final code = parsed['code'] as String? ?? '';
    final target = code.trim().isNotEmpty
        ? 'this code:\n```\n$code\n```'
        : 'the problem "${currentQuestion?.title ?? "the current problem"}"';

    final response = await _toolManager.executeTool('groq', {
      'systemPrompt':
          'Analyze time and space complexity precisely (Big-O), '
          'explain the reasoning briefly, and note the dominant operation.',
      'message': 'Analyze the time and space complexity of $target',
    });

    return AgentExecutionResult(
      responseText: response as String,
      agentName: 'DSA Agent',
      usedTools: const ['groq'],
    );
  }

  Future<AgentExecutionResult> handleDryRun(
    ExecutionContext context,
    DsaQuestion? currentQuestion,
    Map<String, dynamic> parsed,
  ) async {
    final code = parsed['code'] as String? ?? '';
    if (code.trim().isEmpty) {
      return AgentExecutionResult(
        responseText:
            "Paste the code you'd like me to dry-run, along with sample input if you have one.",
        agentName: 'DSA Agent',
      );
    }

    final response = await _toolManager.executeTool('groq', {
      'systemPrompt':
          'Perform a clear step-by-step dry run / trace of this code '
          'with a representative input, showing variable states at each step.',
      'message': 'Code:\n```${parsed['language'] ?? ''}\n$code\n```',
    });

    return AgentExecutionResult(
      responseText: response as String,
      agentName: 'DSA Agent',
      usedTools: const ['groq'],
    );
  }

  Future<AgentExecutionResult> handleSave(
    ExecutionContext context,
    DsaQuestion? currentQuestion,
  ) async {
    if (currentQuestion == null) return _noActiveQuestion();

    await _repo.saveQuestionForUser(context.userId, currentQuestion);

    return AgentExecutionResult(
      responseText:
          "Saved **${currentQuestion.title}** to your bookmarks. "
          "Ask me to 'list saved questions' anytime to revisit it.",
      agentName: 'DSA Agent',
      usedTools: const ['firebase'],
    );
  }

  Future<AgentExecutionResult> handleListSaved(ExecutionContext context) async {
    final saved = await _repo.getSavedQuestions(context.userId);

    if (saved.isEmpty) {
      return AgentExecutionResult(
        responseText:
            "You haven't saved any questions yet. Solve or fetch a problem, then ask me to save it.",
        agentName: 'DSA Agent',
        usedTools: const ['firebase'],
      );
    }

    final list = saved.map((q) => "- ${q.title} (${q.difficulty})").join('\n');
    return AgentExecutionResult(
      responseText: "Your saved questions:\n\n$list",
      agentName: 'DSA Agent',
      usedTools: const ['firebase'],
    );
  }

  Future<AgentExecutionResult> handleRevise(ExecutionContext context) async {
    final saved = await _repo.getSavedQuestions(context.userId);

    if (saved.isEmpty) {
      return AgentExecutionResult(
        responseText:
            "Nothing saved to revise yet - save a few problems first and I'll quiz you on them.",
        agentName: 'DSA Agent',
        usedTools: const ['firebase'],
      );
    }

    saved.shuffle();
    final pick = saved.first;

    return AgentExecutionResult(
      responseText:
          "Revision time! **${pick.title}** (${pick.difficulty})\n\n"
          "${pick.description}\n\nTry solving it again - ask for a hint if you're stuck.",
      agentName: 'DSA Agent',
      usedTools: const ['firebase'],
      updatedMemory: {'currentQuestion': pick.toMap(), 'hintLevel': 0},
    );
  }

  Future<AgentExecutionResult> handleInterviewMode(
    ExecutionContext context,
    DsaQuestion? currentQuestion,
    bool interviewActive,
  ) async {
    if (!interviewActive) {
      final question =
          currentQuestion ??
          await _repo.getTodaysQuestion() ??
          await _gfg.fetchProblemOfTheDay();

      return AgentExecutionResult(
        responseText:
            "**Interview mode started.** I'll act as your interviewer - "
            "no hints unless you ask, and I'll evaluate your approach as you go.\n\n"
            "Problem: **${question.title}** (${question.difficulty})\n\n${question.description}\n\n"
            "Talk me through your approach.",
        agentName: 'DSA Agent',
        updatedMemory: {
          'currentQuestion': question.toMap(),
          'interviewActive': true,
          'hintLevel': 0,
        },
      );
    }

    final response = await _toolManager.executeTool('groq', {
      'systemPrompt':
          'You are a technical interviewer conducting a mock DSA interview. '
          "Respond to the candidate's reasoning realistically - ask clarifying "
          'questions, push on edge cases, and don\'t over-help unless they\'re truly stuck.',
      'message': context.message,
    });

    return AgentExecutionResult(
      responseText: response as String,
      agentName: 'DSA Agent',
      usedTools: const ['groq'],
    );
  }

  AgentExecutionResult _noActiveQuestion() {
    return AgentExecutionResult(
      responseText:
          "You don't have an active problem right now. "
          "Ask for today's problem of the day to get started.",
      agentName: 'DSA Agent',
    );
  }
}
