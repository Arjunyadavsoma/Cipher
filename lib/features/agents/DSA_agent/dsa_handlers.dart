import 'dart:math';

import 'package:mimir_ai/features/agents/DSA_agent/dsa_question.dart';
import 'package:mimir_ai/features/agents/DSA_agent/dsa_respository.dart';
import 'package:mimir_ai/features/agents/DSA_agent/gfg_fetch_service.dart';
import 'package:mimir_ai/features/agents/core/tool_manager.dart';
import 'package:mimir_ai/features/agents/models/agent_context_storage.dart';
import 'package:mimir_ai/features/agents/models/execution_context.dart';
import 'package:mimir_ai/features/agents/models/execution_result.dart';
import 'package:mimir_ai/features/agents/repositories/agent_memory_repository.dart';

/// Contains the execution logic for each DSA intent.
/// Handles state management, LLM tutoring, and Firestore persistence.
class DsaHandlers {
  final DsaRepository _repository;
  final GfgFetchService _gfgService;
  final ToolManager _toolManager;

  DsaHandlers(this._repository, this._gfgService, this._toolManager);

  // ===========================================================================
  // Core Handlers
  // ===========================================================================

  /// GET_POTD: Fetches today's problem, caches it, and loads it into memory.
  Future<AgentExecutionResult> handleGetPotd(
    ExecutionContext context,
    DsaQuestion? currentQuestion,
  ) async {
    if (currentQuestion != null) {
      return _formatQuestionResult(currentQuestion, "Here is today's problem again:");
    }

    DsaQuestion? question = await _repository.getTodaysQuestion();

    if (question == null) {
      try {
        question = await _gfgService.fetchProblemOfTheDay();
        await _repository.cacheDailyQuestion(question);
      } catch (e) {
        return AgentExecutionResult(
          responseText: "Today's question couldn't be retrieved from GeeksforGeeks. Please try again later.",
          agentName: 'DSA Agent',
          success: false,
          errorMessage: e.toString(),
        );
      }
    }

    // Sticky State: Save to memory and reset hint level
    await AgentMemoryRepository.instance.saveAgentContext(
      userId: context.userId,
      agentId: 'dsa_agent',
      storage: AgentContextStorage.firestore,
      data: {
        'currentQuestion': question.toMap(),
        'hintLevel': 0,
        'interviewActive': false,
      },
    );

    return _formatQuestionResult(question, "Today's GeeksforGeeks Problem is ready.");
  }

  /// EXPLAIN: Provides a clear, educational breakdown of the current problem.
  Future<AgentExecutionResult> handleExplain(
    ExecutionContext context,
    DsaQuestion? currentQuestion,
  ) async {
    if (currentQuestion == null) {
      return _noProblemLoadedError();
    }

    final prompt = "Explain this DSA problem clearly to a student. Break down the description, constraints, and examples. Be encouraging.\n\n"
        "Title: ${currentQuestion.title}\nDescription: ${currentQuestion.description}\nTags: ${currentQuestion.tags.join(', ')}";

    return _generateTutorResponse(context, prompt, "You are an expert DSA tutor. Explain concepts clearly and educationally.");
  }

  /// HINT: Socratic progressive hints. Never reveals the answer outright.
  Future<AgentExecutionResult> handleHint(
    ExecutionContext context,
    DsaQuestion? currentQuestion,
    int hintLevel,
  ) async {
    if (currentQuestion == null) {
      return _noProblemLoadedError();
    }

    String hintPrompt;
    if (hintLevel == 0) {
      hintPrompt = "Give a vague observation about the problem constraints. DO NOT mention the algorithm.";
    } else if (hintLevel == 1) {
      hintPrompt = "Suggest a brute-force algorithm idea. DO NOT provide the optimal solution.";
    } else if (hintLevel == 2) {
      hintPrompt = "Suggest the optimal algorithm/data structure to use. DO NOT write code.";
    } else {
      hintPrompt = "Provide pseudocode for the optimal solution.";
    }

    final prompt = "$hintPrompt\n\nProblem: ${currentQuestion.title}\n${currentQuestion.description}";

    // Increment hint level in memory
    await AgentMemoryRepository.instance.saveAgentContext(
      userId: context.userId,
      agentId: 'dsa_agent',
      storage: AgentContextStorage.firestore,
      data: {'hintLevel': hintLevel + 1},
    );

    return _generateTutorResponse(context, prompt, "You are an expert DSA tutor. Follow the instructions exactly. Do not reveal more than asked.");
  }

  /// REVEAL_SOLUTION: User explicitly gave up. Provides optimal code and explanation.
  Future<AgentExecutionResult> handleRevealSolution(
    ExecutionContext context,
    DsaQuestion? currentQuestion,
    Map<String, dynamic> parsed,
  ) async {
    if (currentQuestion == null) {
      return _noProblemLoadedError();
    }

    final lang = (parsed['language'] as String?)?.isNotEmpty == true ? parsed['language'] : "Python";
    final prompt = "Provide the optimal solution in $lang for this problem. Explain the code line by line.\nProblem: ${currentQuestion.title}\n${currentQuestion.description}";

    return _generateTutorResponse(context, prompt, "You are an expert DSA tutor providing the final solution.");
  }

  /// REVIEW_CODE: Anti-hallucination strict review. Tracks progress if correct.
  ///
  /// NOTE: your latest version of this handler extracted `code`/`lang` and
  /// started building `prompt`, but the prompt was never finished (no code
  /// block, no review-format instructions) before being passed to
  /// _generateTutorResponse, and the progress-tracking step from your
  /// original version (mark the question solved if the review says the
  /// code was correct) was dropped entirely. Restored both below - if you
  /// deliberately meant to drop progress tracking here, delete the
  /// eval/progress block at the bottom of this method.
  Future<AgentExecutionResult> handleReviewCode(
    ExecutionContext context,
    DsaQuestion? currentQuestion,
    Map<String, dynamic> parsed,
  ) async {
    final code = parsed['code'] as String? ?? '';
    if (code.isEmpty) {
      return AgentExecutionResult(
        responseText: "It looks like you want a code review, but I didn't see any code. Please paste your code!",
        agentName: 'DSA Agent',
      );
    }

    final lang = parsed['language'] ?? 'unknown';
    var prompt = "Review this $lang code. \n";
    if (currentQuestion != null) {
      prompt += "Problem: ${currentQuestion.title}\n${currentQuestion.description}\n\n";
    }

    prompt += """
Code:
```$lang
$code
```

Step 1: Mentally dry-run the code with a small sample input. Write down the variable states.
Step 2: Identify any edge cases where the code would crash (e.g., empty arrays, nulls, overflow).
Step 3: Provide your review in this exact markdown format:
### 🧮 Complexity
- Time: O(...)
- Space: O(...)
### ✅ Strengths
- ...
### ❌ Weaknesses / Bugs
- ...
### 🛠️ Suggested Fix
- ...
""";

    final reviewResult = await _generateTutorResponse(
      context,
      prompt,
      "You are a strict but encouraging senior engineer conducting a code review. Format output with markdown headings.",
    );

    // PROGRESS TRACKING: Check if code was correct
    try {
      final evalPrompt = "Based on this review, was the user's original code completely correct and optimal? Answer ONLY 'YES' or 'NO'.\n\nReview: ${reviewResult.responseText}";
      final evalResult = await _toolManager.executeTool('groq', {
        'systemPrompt': 'You are a strict evaluator. Only output YES or NO.',
        'message': evalPrompt,
        'history': const [],
      });

      if (evalResult.toString().trim().toUpperCase() == 'YES') {
        final progress = await _repository.getUserProgress(context.userId);
        progress.totalSolved += 1;
        String diff = currentQuestion?.difficulty ?? 'Easy';
        progress.difficultySolved[diff] = (progress.difficultySolved[diff] ?? 0) + 1;
        await _repository.updateUserProgress(context.userId, progress);
      }
    } catch (_) {
      // Silent fail on progress tracking to not interrupt user experience
    }

    return reviewResult;
  }

  /// COMPLEXITY: Analyzes time and space tradeoffs.
  Future<AgentExecutionResult> handleComplexity(
    ExecutionContext context,
    DsaQuestion? currentQuestion,
    Map<String, dynamic> parsed,
  ) async {
    final code = parsed['code'] as String? ?? '';
    var prompt = "Analyze the time and space complexity (Best, Worst, Average) and explain the tradeoffs.\n";

    if (code.isNotEmpty) {
      prompt += "Code:\n```\n$code\n```";
    } else if (currentQuestion != null) {
      prompt += "Problem: ${currentQuestion.title}\nOptimal Approach Expected: ${currentQuestion.timeComplexity ?? 'Unknown'} / ${currentQuestion.spaceComplexity ?? 'Unknown'}";
    } else {
      return _noProblemLoadedError();
    }

    return _generateTutorResponse(context, prompt, "You are an expert DSA tutor. Explain complexity in a markdown table format.");
  }

  /// DRY_RUN: Step-by-step simulation of code.
  Future<AgentExecutionResult> handleDryRun(
    ExecutionContext context,
    DsaQuestion? currentQuestion,
    Map<String, dynamic> parsed,
  ) async {
    final code = parsed['code'] as String? ?? '';
    if (code.isEmpty) {
      return AgentExecutionResult(
        responseText: "Please paste the code you want me to dry run.",
        agentName: 'DSA Agent',
      );
    }

    final prompt = "Perform a step-by-step dry run of this code. Use the sample input if a problem is loaded, or explain the execution flow line by line.\nCode:\n```\n$code\n```";
    return _generateTutorResponse(context, prompt, "You are an expert DSA tutor. Execute code mentally and present the dry run in a step-by-step markdown table.");
  }

  // ===========================================================================
  // Persistence & Revision Handlers
  // ===========================================================================

  /// SAVE: Bookmarks the current question to Firestore.
  Future<AgentExecutionResult> handleSave(ExecutionContext context, DsaQuestion? currentQuestion) async {
    if (currentQuestion == null) {
      return _noProblemLoadedError();
    }

    await _repository.saveQuestionForUser(context.userId, currentQuestion);
    return AgentExecutionResult(
      responseText: "✅ **${currentQuestion.title}** has been saved to your revision queue.",
      agentName: 'DSA Agent',
      usedTools: const ['firebase'],
    );
  }

  /// LIST_SAVED: Fetches all saved questions for the user.
  Future<AgentExecutionResult> handleListSaved(ExecutionContext context) async {
    final saved = await _repository.getSavedQuestions(context.userId);
    if (saved.isEmpty) {
      return AgentExecutionResult(
        responseText: "You haven't saved any questions yet. Try saving today's problem for later revision!",
        agentName: 'DSA Agent',
        usedTools: const ['firebase'],
      );
    }

    final buffer = StringBuffer("**Your Saved Questions:**\n\n");
    for (final q in saved) {
      buffer.writeln("- **${q.title}** (${q.difficulty}) - Tags: ${q.tags.join(', ')}");
    }
    buffer.writeln("\n_Ask me to 'open' a specific one or 'quiz me' on them._");

    return AgentExecutionResult(
      responseText: buffer.toString().trim(),
      agentName: 'DSA Agent',
      usedTools: const ['firebase'],
    );
  }

  /// REVISE: Picks a random saved question and loads it into context.
  Future<AgentExecutionResult> handleRevise(ExecutionContext context) async {
    final saved = await _repository.getSavedQuestions(context.userId);
    if (saved.isEmpty) {
      return AgentExecutionResult(
        responseText: "Your revision queue is empty. Save some problems first!",
        agentName: 'DSA Agent',
        usedTools: const ['firebase'],
      );
    }

    final random = Random();
    final targetQuestion = saved[random.nextInt(saved.length)];

    // Load it into context
    await AgentMemoryRepository.instance.saveAgentContext(
      userId: context.userId,
      agentId: 'dsa_agent',
      storage: AgentContextStorage.firestore,
      data: {
        'currentQuestion': targetQuestion.toMap(),
        'hintLevel': 0,
        'interviewActive': false,
      },
    );

    return AgentExecutionResult(
      responseText: "🎯 **Revision Time!**\n\nLet's revise: **${targetQuestion.title}** (${targetQuestion.difficulty}).\n\n${targetQuestion.description}\n\n_Try to solve it, or ask for a hint if you're stuck!_",
      agentName: 'DSA Agent',
      usedTools: const ['firebase'],
    );
  }

  // ===========================================================================
  // Interview Mode
  // ===========================================================================

  /// INTERVIEW_MODE: Acts as a strict FAANG interviewer.
  Future<AgentExecutionResult> handleInterviewMode(
    ExecutionContext context,
    DsaQuestion? currentQuestion,
    bool interviewActive,
  ) async {
    if (!interviewActive) {
      if (currentQuestion == null) {
        return _noProblemLoadedError();
      }

      await AgentMemoryRepository.instance.saveAgentContext(
        userId: context.userId,
        agentId: 'dsa_agent',
        storage: AgentContextStorage.firestore,
        data: {'interviewActive': true},
      );

      return AgentExecutionResult(
        responseText: "🎤 **Interview Mode Activated.**\n\nI will act as your interviewer. I will NOT reveal answers. I will only ask guiding questions and evaluate your responses. \n\nLet's start with today's problem: **${currentQuestion.title}**.\n\nHow would you approach this?",
        agentName: 'DSA Agent',
      );
    } else {
      // Continue interview
      final prompt = "The user is in an interview simulation. Evaluate their response. Do not give the answer. Ask a guiding question or point out an edge case.\nUser said: ${context.message}";
      return _generateTutorResponse(context, prompt, "You are a strict FAANG interviewer. Never reveal the answer. Push the candidate to think.");
    }
  }

  // ===========================================================================
  // Utilities
  // ===========================================================================

  AgentExecutionResult _noProblemLoadedError() {
    return AgentExecutionResult(
      responseText: "I don't have a problem loaded right now. Ask me for 'today's problem' first!",
      agentName: 'DSA Agent',
    );
  }

  Future<AgentExecutionResult> _generateTutorResponse(
    ExecutionContext context,
    String userMessage,
    String systemInstruction,
  ) async {
    try {
      final raw = await _toolManager.executeTool('groq', {
        'systemPrompt': systemInstruction,
        'message': userMessage,
        'history': context.recentMessages.map((m) => m.toGroqFormat()).toList(),
      });

      return AgentExecutionResult(
        responseText: (raw as String).trim(),
        agentName: 'DSA Agent',
        usedTools: const ['groq'],
      );
    } catch (e) {
      return AgentExecutionResult(
        responseText: "I couldn't generate a response just now. Please try again.",
        agentName: 'DSA Agent',
        success: false,
        errorMessage: e.toString(),
      );
    }
  }

  AgentExecutionResult _formatQuestionResult(DsaQuestion q, String intro) {
    final buffer = StringBuffer(intro);
    buffer.writeln("\n\n**Difficulty:** ${q.difficulty}");
    buffer.writeln("**Tags:** ${q.tags.join(', ')}");
    buffer.writeln("\n**Problem:** ${q.title}");
    buffer.writeln("\n${q.description}");
    buffer.writeln("\n🔗 **Link:** [Open on GeeksforGeeks](${q.url})");
    buffer.writeln("\n_You can ask me to 'explain', 'give a hint', or 'review my code'._");

    return AgentExecutionResult(
      responseText: buffer.toString().trim(),
      agentName: 'DSA Agent',
      usedTools: const ['firebase', 'http'],
    );
  }
}