import 'dart:convert';

import '../core/base_agent.dart';
import '../core/tool_manager.dart';
import '../models/agent_context_storage.dart';
import '../models/execution_context.dart';
import '../models/execution_result.dart';
import '../repositories/agent_memory_repository.dart';

/// Handles academic / topic research, modeled loosely on Google ADK's
/// "academic-research" sample agent: given a seminal paper or a topic,
/// it (1) analyzes/summarizes the source, (2) searches for related or
/// citing work, and (3) synthesizes likely future research directions.
///
/// Three intents:
///   1. ANALYZE  - user gives a paper (title/DOI/URL) or pasted abstract
///                 and wants it broken down (contributions, methodology,
///                 findings).
///   2. FIND_RELATED - user wants recent/citing papers or work related to
///                 a topic or a previously analyzed paper.
///   3. SYNTHESIZE - user wants future research directions / gaps drawn
///                 from an analyzed paper plus whatever related work has
///                 been found so far.
///
/// Follow-ups ("find more on that", "what should I look into next") reuse
/// whatever was last analyzed/found via agentMemory, the same sticky-state
/// pattern EmailAgent uses for pendingDraft / pendingSearchResults.
class ResearchAgent implements BaseAgent {
  @override
  String get id => 'research_agent';

  @override
  String get name => 'Research Agent';

  @override
  String get description =>
      'Helps analyze academic papers or topics, find related/citing work, '
      'and suggest future research directions. Use for any request '
      'involving a research paper, DOI, academic topic, literature '
      'search, or "what should I read/explore next" style follow-ups.';

  @override
  String get systemPrompt => '''
You are the Research Agent inside Mimir AI. Classify the user's message into
exactly one of these intents:

- ANALYZE: user provides a paper (title, authors, DOI, URL) or pastes an
  abstract/excerpt and wants it broken down - key contributions,
  methodology, findings, limitations.
- FIND_RELATED: user wants recent papers, citing work, or general
  literature related to a topic or a paper already discussed in this
  conversation. This is a lookup, not a request to explain any single
  paper in depth.
- SYNTHESIZE: user wants future research directions, open problems, or
  gaps to explore, drawing on a paper and/or related work already
  discussed.
- OTHER: anything else research-related that doesn't fit the above.

For ANALYZE, also extract:
- paperTitle: the title if identifiable, else ""
- paperQuery: the best search string to locate this paper (title +
  authors, or DOI/URL as given), else ""
- pastedContent: if the user pasted an abstract/excerpt directly, put
  it here verbatim, else ""

For FIND_RELATED, also extract:
- topic: the topic or paper to find related work for. If the user is
  clearly referring to a paper already analyzed earlier in this
  conversation ("find papers that cite it", "what else is related"),
  leave this "" and set useLastPaper to true.
- useLastPaper: true if this should use the most recently analyzed
  paper as the anchor, false if a new topic/paper was given.

For SYNTHESIZE, also extract:
- focusHint: any specific angle the user wants ("gaps in evaluation",
  "practical applications", etc.), else "".

Always respond with JSON only, no other text, in this exact shape:
{
  "intent": "analyze" | "find_related" | "synthesize" | "other",
  "paperTitle": "<title, or empty string>",
  "paperQuery": "<search string, or empty string>",
  "pastedContent": "<pasted abstract/excerpt, or empty string>",
  "topic": "<topic for find_related, or empty string>",
  "useLastPaper": true | false,
  "focusHint": "<focus angle for synthesize, or empty string>",
  "responseText": "<short natural-language message to show the user>"
}
''';

  @override
  List<String> get tools => ['groq', 'research'];

  @override
  AgentContextStorage get contextStorage => AgentContextStorage.firestore;

  /// Phrases that indicate the user is continuing the research thread
  /// rather than starting something new - same fixed-list tradeoff
  /// EmailAgent uses for its follow-up detection: predictable, easy to
  /// extend, no false positives on short unrelated replies.
  static const _continuationPhrases = [
    'find more',
    'more like that',
    'related to that',
    'related work',
    'who cites',
    'what cites',
    'citing papers',
    'papers that cite',
    'what should i read next',
    'what should i explore next',
    'future directions',
    'next steps',
    'open problems',
    'research gaps',
    'what else',
    'dig deeper',
    'go deeper',
    'expand on that',
    'tell me more',
  ];

  static bool looksLikeContinuation(String message) {
    final lower = message.toLowerCase();
    return _continuationPhrases.any(lower.contains);
  }

  @override
  Future<AgentExecutionResult> execute(ExecutionContext context) async {
    Map<String, dynamic> parsed;
    try {
      parsed = await _classify(context);
    } catch (e) {
      // ignore: avoid_print
      print('ResearchAgent._classify: threw: $e');
      return AgentExecutionResult(
        responseText:
            "I had trouble understanding that request — could you try "
            "rephrasing it?",
        agentName: name,
        success: false,
        errorMessage: 'classify() failed: $e',
      );
    }

    if (parsed.isEmpty) {
      // _classify() itself never throws on bad JSON - _parseJson()
      // swallows that and returns {} - so this is the "model responded
      // with something we couldn't parse at all" case, not a crash.
      return AgentExecutionResult(
        responseText:
            "I had trouble understanding that request — could you try "
            "rephrasing it?",
        agentName: name,
        success: false,
        errorMessage: 'classify() returned unparseable/empty JSON',
      );
    }

    final intent = parsed['intent'] as String? ?? 'other';

    try {
      switch (intent) {
        case 'analyze':
          return await _handleAnalyze(context, parsed);
        case 'find_related':
          return await _handleFindRelated(context, parsed);
        case 'synthesize':
          return await _handleSynthesize(context, parsed);
        default:
          return AgentExecutionResult(
            responseText: parsed['responseText'] as String? ?? '',
            agentName: name,
            usedTools: const ['groq'],
          );
      }
    } catch (e) {
      // Safety net only - each handler below has its own specific
      // try/catch around its risky calls (tool calls, memory writes) with
      // a tailored message. This one just guarantees that if a handler
      // is ever added/edited without that discipline, the user still
      // sees something more useful than the generic AgentExecutor
      // failure text, and the real cause lands in errorMessage/logs.
      return AgentExecutionResult(
        responseText:
            "Something went wrong while working on that — mind trying "
            "again?",
        agentName: name,
        success: false,
        errorMessage: '$intent handler failed: $e',
      );
    }
  }

  // ---------- ANALYZE ----------

  Future<AgentExecutionResult> _handleAnalyze(
    ExecutionContext context,
    Map<String, dynamic> parsed,
  ) async {
    final paperTitle = (parsed['paperTitle'] as String? ?? '').trim();
    final paperQuery = (parsed['paperQuery'] as String? ?? '').trim();
    final pastedContent = (parsed['pastedContent'] as String? ?? '').trim();

    String sourceText;
    String resolvedTitle = paperTitle;

    if (pastedContent.isNotEmpty) {
      sourceText = pastedContent;
    } else if (paperQuery.isNotEmpty) {
      try {
        final found = await ToolManager.instance.executeTool('research', {
          'type': 'lookup',
          'query': paperQuery,
        }) as Map<String, String>;

        if (found.isEmpty) {
          return AgentExecutionResult(
            responseText:
                "I couldn't find that paper — could you paste the "
                "abstract, or share a DOI/URL?",
            agentName: name,
            usedTools: const ['research'],
          );
        }

        resolvedTitle = found['title'] ?? paperTitle;
        sourceText =
            "${found['title']}\n${found['authors'] ?? ''}\n\n${found['abstract'] ?? ''}";
      } catch (e) {
        return AgentExecutionResult(
          responseText: "I couldn't look that paper up — $e",
          agentName: name,
          success: false,
          errorMessage: e.toString(),
        );
      }
    } else {
      return AgentExecutionResult(
        responseText:
            "Share a paper title, DOI/URL, or paste the abstract and "
            "I'll break it down for you.",
        agentName: name,
      );
    }

    final analysisPrompt =
        "Analyze this paper. Cover: (1) core contribution, (2) "
        "methodology, (3) key findings, (4) limitations. Be concise.\n\n"
        "$sourceText";

    String analysis;
    try {
      analysis = await ToolManager.instance.executeTool('groq', {
        'systemPrompt':
            'You are the Research Agent. Analyze academic papers clearly '
            'and concisely, structured under short headers.',
        'message': analysisPrompt,
        'history': const [],
      }) as String;
    } catch (e) {
      return AgentExecutionResult(
        responseText:
            "I found the paper but hit an error writing the analysis — "
            "mind trying again?",
        agentName: name,
        success: false,
        errorMessage: 'groq analysis call failed: $e',
        usedTools: paperQuery.isNotEmpty ? const ['research'] : const [],
      );
    }

    // Memory save failing (e.g. Firestore rules not yet covering
    // 'research_agent' docs the way they cover 'email_agent') shouldn't
    // block the user from seeing the analysis they asked for - it just
    // means follow-ups like "find related work" won't have this paper
    // to anchor on. Surface that as a soft note rather than an error.
    var responseText = analysis;
    try {
      await AgentMemoryRepository.instance.saveAgentContext(
        userId: context.userId,
        agentId: id,
        storage: contextStorage,
        data: {
          'lastPaper': {
            'title': resolvedTitle.isNotEmpty ? resolvedTitle : 'Untitled',
            'sourceText': sourceText,
            'analysis': analysis,
          },
          'lastRelatedWork': null,
        },
      );
    } catch (e) {
      responseText =
          "$analysis\n\n_(Note: couldn't save this for follow-up "
          "questions — you may need to re-share it next time.)_";
    }

    return AgentExecutionResult(
      responseText: responseText,
      agentName: name,
      usedTools: paperQuery.isNotEmpty ? const ['research', 'groq'] : const ['groq'],
    );
  }

  // ---------- FIND_RELATED ----------

  Future<AgentExecutionResult> _handleFindRelated(
    ExecutionContext context,
    Map<String, dynamic> parsed,
  ) async {
    final topic = (parsed['topic'] as String? ?? '').trim();
    final useLastPaper = parsed['useLastPaper'] as bool? ?? false;

    final lastPaper = context.agentMemory?['lastPaper'] as Map?;

    String query;
    if (topic.isNotEmpty) {
      query = topic;
    } else if (useLastPaper && lastPaper != null) {
      query = lastPaper['title'] as String? ?? '';
    } else {
      return AgentExecutionResult(
        responseText:
            "What topic or paper should I find related work for?",
        agentName: name,
      );
    }

    if (query.isEmpty) {
      return AgentExecutionResult(
        responseText:
            "I don't have a paper to search from yet — analyze one first, "
            "or give me a topic.",
        agentName: name,
      );
    }

    List<Map<String, String>> results;
    try {
      results = await ToolManager.instance.executeTool('research', {
        'type': 'search',
        'query': query,
        'maxResults': 10,
      }) as List<Map<String, String>>;
    } catch (e) {
      return AgentExecutionResult(
        responseText: "I couldn't search for related work — $e",
        agentName: name,
        success: false,
        errorMessage: e.toString(),
      );
    }

    if (results.isEmpty) {
      return AgentExecutionResult(
        responseText: "I didn't find related work for \"$query\".",
        agentName: name,
        usedTools: const ['research'],
      );
    }

    var memorySaveFailed = false;
    try {
      await AgentMemoryRepository.instance.saveAgentContext(
        userId: context.userId,
        agentId: id,
        storage: contextStorage,
        data: {'lastRelatedWork': results},
      );
    } catch (_) {
      // Same soft-degrade as _handleAnalyze: show the results either way,
      // just warn that a follow-up ("what should I explore next") won't
      // see this list.
      memorySaveFailed = true;
    }

    final citations = results
        .map((r) => Citation(title: r['title'] ?? '', url: r['url'] ?? ''))
        .toList();

    final buffer = StringBuffer();
    buffer.writeln("Found ${results.length} related paper(s):");
    buffer.writeln();
    for (final r in results) {
      buffer.writeln("- **${r['title']}**${r['year'] != null ? ' (${r['year']})' : ''}");
      if ((r['snippet'] ?? '').isNotEmpty) buffer.writeln("  ${r['snippet']}");
    }
    if (memorySaveFailed) {
      buffer.writeln();
      buffer.writeln(
        "_(Note: couldn't save this list for follow-up questions.)_",
      );
    }

    return AgentExecutionResult(
      responseText: buffer.toString().trim(),
      agentName: name,
      usedTools: const ['research'],
      citations: citations,
    );
  }

  // ---------- SYNTHESIZE ----------

  Future<AgentExecutionResult> _handleSynthesize(
    ExecutionContext context,
    Map<String, dynamic> parsed,
  ) async {
    final focusHint = (parsed['focusHint'] as String? ?? '').trim();
    final lastPaper = context.agentMemory?['lastPaper'] as Map?;
    final lastRelatedWork = context.agentMemory?['lastRelatedWork'] as List?;

    if (lastPaper == null) {
      return AgentExecutionResult(
        responseText:
            "Analyze a paper first (share a title, DOI, or abstract) and "
            "I'll help map out future research directions from it.",
        agentName: name,
      );
    }

    final buffer = StringBuffer();
    buffer.writeln("Paper: ${lastPaper['title']}");
    buffer.writeln();
    buffer.writeln("Analysis:\n${lastPaper['analysis']}");
    if (lastRelatedWork != null && lastRelatedWork.isNotEmpty) {
      buffer.writeln();
      buffer.writeln("Related/citing work found so far:");
      for (final r in lastRelatedWork.cast<Map>()) {
        buffer.writeln("- ${r['title']}");
      }
    }

    final synthesisPrompt =
        "Based on the paper analysis and related work below, propose 3-5 "
        "concrete future research directions or open problems"
        "${focusHint.isNotEmpty ? ', focusing on: $focusHint' : ''}. "
        "Be specific, not generic.\n\n${buffer.toString()}";

    String synthesis;
    try {
      synthesis = await ToolManager.instance.executeTool('groq', {
        'systemPrompt':
            'You are the Research Agent. Propose specific, well-reasoned '
            'future research directions grounded in the given material.',
        'message': synthesisPrompt,
        'history': const [],
      }) as String;
    } catch (e) {
      return AgentExecutionResult(
        responseText:
            "I hit an error putting the future directions together — "
            "mind trying again?",
        agentName: name,
        success: false,
        errorMessage: 'groq synthesis call failed: $e',
      );
    }

    return AgentExecutionResult(
      responseText: synthesis,
      agentName: name,
      usedTools: const ['groq'],
    );
  }

  // ---------- CLASSIFICATION ----------

  Future<Map<String, dynamic>> _classify(ExecutionContext context) async {
    final history = context.recentMessages.map((m) => m.toGroqFormat()).toList();

    final rawResponse = await ToolManager.instance.executeTool('groq', {
      'systemPrompt': systemPrompt,
      'message': _buildPrompt(context),
      'history': history,
    }) as String;

    final parsed = _parseJson(rawResponse);
    if (parsed.isEmpty) {
      // ignore: avoid_print
      print('ResearchAgent._classify: unparseable response: $rawResponse');
    }
    return parsed;
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

  Map<String, dynamic> _parseJson(String text) {
    try {
      final start = text.indexOf('{');
      final end = text.lastIndexOf('}');
      if (start == -1 || end == -1) return {};
      return jsonDecode(text.substring(start, end + 1)) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }
}