import 'dart:convert';
import 'package:cipher_ai/features/agents/research_agent/research_pipeline/cache_manager.dart';
import 'package:cipher_ai/features/agents/research_agent/research_pipeline/planner.dart';
import 'package:cipher_ai/features/agents/research_agent/research_pipeline/report_builder.dart';
import 'package:flutter/foundation.dart';

import 'package:flutter_background_service/flutter_background_service.dart';
import '../core/base_agent.dart';
import '../core/tool_manager.dart';
import '../models/agent_context_storage.dart';
import '../models/execution_context.dart';
import '../models/execution_result.dart';
import '../repositories/agent_memory_repository.dart';

// Pipeline Imports

import 'pipeline/search_manager.dart';
import 'pipeline/crawl_manager.dart';
import 'pipeline/structured_extractor.dart';

class ResearchAgent implements BaseAgent {

  Future<void> startBackgroundResearch(String topic) async {
    final service = FlutterBackgroundService();
    
    // Start the foreground service
    bool started = await service.startService();
    
    if (started) {
      // Tell the service what to research
      service.invoke('startResearch', {'topic': topic});
    }
  }
  @override
  String get id => 'research_agent';

  @override
  String get name => 'Research Agent';

  @override
  String get description =>
      'Performs deep, multi-step research on any topic. Plans queries, searches web/community/academic sources, crawls and chunks content, extracts structured facts, and writes a comprehensive report.';

  @override
  String get systemPrompt => '''
You are the Research Agent inside cipher AI. Classify the user's message into
exactly one of these intents:

- DEEP_RESEARCH: User wants a comprehensive, multi-step research report on a topic.
- ANALYZE: user provides a specific paper (title, authors, DOI, URL) or pastes an
  abstract/excerpt and wants it broken down.
- OTHER: anything else research-related that doesn't fit the above.

Always respond with JSON only, no other text, in this exact shape:
{
  "intent": "deep_research" | "analyze" | "other",
  "topic": "<the topic to research>",
  "responseText": "<short natural-language message to show the user>"
}
''';

  static const _continuationPhrases = [
    'find more', 'more like that', 'related to that', 'related work', 'who cites',
    'what cites', 'citing papers', 'papers that cite', 'what should i read next',
    'what should i explore next', 'future directions', 'next steps', 'open problems',
    'research gaps', 'what else', 'dig deeper', 'go deeper', 'expand on that', 'tell me more',
  ];

  static bool looksLikeContinuation(String message) {
    final lower = message.toLowerCase();
    return _continuationPhrases.any(lower.contains);
  }

  @override
  List<String> get tools => ['groq', 'web', 'community', 'youtube', 'stackoverflow', 'wikipedia', 'research'];

  @override
  AgentContextStorage get contextStorage => AgentContextStorage.firestore;

  // Pipeline Components
  final _planner = ResearchPlanner();
  final _searchManager = SearchManager();
  final _crawlManager = CrawlManager();
  final _extractor = StructuredExtractor();
  final _reportBuilder = ReportBuilder();
  final _cache = ResearchCacheManager();

  @override
  Future<AgentExecutionResult> execute(ExecutionContext context) async {
    Map<String, dynamic> parsed;
    try {
      parsed = await _classify(context);
    } catch (e) {
      return AgentExecutionResult(responseText: "I had trouble understanding that request.", agentName: name, success: false);
    }

    final intent = parsed['intent'] as String? ?? 'other';
    final topic = (parsed['topic'] as String? ?? '').trim().isNotEmpty ? parsed['topic'] as String : context.message;

    try {
      switch (intent) {
        case 'deep_research':
          return await _handleDeepResearch(context, topic);
        default:
          return AgentExecutionResult(responseText: parsed['responseText'] as String? ?? '', agentName: name, usedTools: const ['groq']);
      }
    } catch (e) {
      return AgentExecutionResult(responseText: "Something went wrong during the research pipeline.", agentName: name, success: false, errorMessage: '$intent handler failed: $e');
    }
  }

  // ---------- DEEP RESEARCH PIPELINE (LOCAL & FREE) ----------

  Future<AgentExecutionResult> _handleDeepResearch(ExecutionContext context, String topic) async {
    // Stage 1: Cache Check
    try {
      final cached = await _cache.getCachedResults(topic);
      if (cached != null && cached.isNotEmpty) {
        debugPrint("Research Cache HIT for: $topic");
        final extractedFacts = await _extractor.extract(topic, cached);
        final report = await _reportBuilder.buildReport(topic, extractedFacts.cast<Map<String, dynamic>>());
        return AgentExecutionResult(responseText: report, agentName: name, usedTools: const ['cache', 'groq']);
      }
    } catch (_) {}

    // Stage 2: Planning
    final subQueries = await _planner.createPlan(topic);

    // Stage 3: Multi-Search & Deduplication
    final searchFutures = <Future<List<Map<String, String>>>>[];
    for (final q in subQueries) {
      searchFutures.add(_searchManager.searchAll(q));
    }

    final searchResults = await Future.wait(searchFutures);
    final allUrls = searchResults.expand((list) => list).toSet().toList();

    if (allUrls.isEmpty) {
      return AgentExecutionResult(responseText: "I couldn't find any information on '$topic'.", agentName: name);
    }

    // Stage 4: Parallel Crawl & Chunking
    final topUrls = allUrls.take(10).toList();
    final chunks = await _crawlManager.fetchAndChunk(topUrls);

    if (chunks.isEmpty) {
      for (final r in allUrls.take(10)) {
        chunks.add({'title': r['title'] ?? '', 'url': r['url'] ?? '', 'text': r['snippet'] ?? ''});
      }
    }

    await _cache.cacheResults(topic, chunks);

    // Stage 5: Structured Information Extraction
    final extractedFacts = await _extractor.extract(topic, chunks);

    // Stage 6: Report Generation
    final report = await _reportBuilder.buildReport(topic, extractedFacts);

    // Stage 7: Save to Long-term Memory
    try {
      await AgentMemoryRepository.instance.saveAgentContext(
        userId: context.userId,
        agentId: id,
        storage: contextStorage,
        data: {
          'lastPaper': {
            'title': 'Deep Research: $topic',
            'sourceText': report,
            'analysis': report,
          },
        },
      );
    } catch (_) {}

    final citations = chunks
        .where((r) => r['url'] != null && r['url']!.isNotEmpty)
        .map((r) => Citation(title: r['title'] ?? '', url: r['url'] ?? ''))
        .toSet()
        .toList();

    return AgentExecutionResult(
      responseText: report,
      agentName: name,
      usedTools: const ['web', 'community', 'research', 'youtube', 'stackoverflow', 'wikipedia', 'groq', 'cache'],
      citations: citations,
    );
  }

  // ---------- CLASSIFICATION ----------
  Future<Map<String, dynamic>> _classify(ExecutionContext context) async {
    final rawResponse = await ToolManager.instance.executeTool('groq', {
      'systemPrompt': systemPrompt,
      'message': context.message,
      'history': const [],
      'temperature': 0.0,
    }) as String;

    try {
      final start = rawResponse.indexOf('{');
      final end = rawResponse.lastIndexOf('}');
      if (start == -1 || end == -1) return {};
      return jsonDecode(rawResponse.substring(start, end + 1)) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }
}