import 'dart:convert';

import 'package:mimir_ai/app/features/rss/models/rss_article.dart';
import 'package:mimir_ai/app/features/rss/models/rss_feed_source.dart';
import 'package:mimir_ai/app/features/rss/models/rss_source.dart';

import '../core/base_agent.dart';
import '../core/tool_manager.dart';
import '../models/agent_context_storage.dart';
import '../models/execution_context.dart';
import '../models/execution_result.dart';

/// A professional, stateless agent responsible for fetching, listing,
/// and summarizing news from RSS feeds.
///
/// It routes natural-language requests into four specific intents:
///   1. `LATEST`           - Lists the most recent articles.
///   2. `SUMMARIZE_24H`    - Generates a written digest across all feeds
///                           within a specific time window (default: 24h).
///   3. `SUMMARIZE_SOURCE` - Generates a digest scoped to a single named source.
///   4. `OTHER`            - Catch-all for news-adjacent queries.
///
/// It merges the user's saved Supabase feeds with the global defaults,
/// gracefully handles malformed LLM JSON, and deduplicates articles
/// before summarization to ensure high-quality digests.
class NewsAgent implements BaseAgent {
  @override
  String get id => 'news_agent';

  @override
  String get name => 'Newsagent';

  @override
  String get description =>
      'Fetches and summarizes news from the user\'s saved RSS feeds. '
      'Use for any request asking for the latest news, a digest of recent '
      'news (e.g. "last 24 hours"), or a summary of a specific saved '
      'source by name.';

  /// Defensive caps to keep token usage and response latency bounded.
  static const int _maxArticlesForSummary = 40;
  static const int _maxArticlesForLatestList = 15;

  /// Hard ceiling on characters of per-article body text sent to the
  /// summarizer. Prevents a single verbose article from monopolizing
  /// the LLM's context window.
  static const int _maxCharsPerArticleInSummary = 1200;

  @override
  String get systemPrompt => '''
You are the News Agent inside Mimir AI. Your role is to classify the
user's most recent message into exactly one of the intents below and
extract the supporting fields.

Intents
-------
- LATEST            : The user wants to see recent articles as a list.
                      Example phrases: "latest news", "what's new",
                      "show me recent articles", "what's on BBC".
                      Use this whenever the user asks to SEE/LIST news
                      rather than READ A WRITTEN SUMMARY of it. A source
                      name MAY be mentioned; if so, set "sourceName".
- SUMMARIZE_24H     : The user wants a written digest covering a time
                      window across all feeds. Examples: "summarize the
                      last 24 hours", "catch me up on today's news",
                      "what happened today", "give me a news recap".
- SUMMARIZE_SOURCE  : The user wants a written digest scoped to ONE
                      specific named source. Examples: "summarize BBC",
                      "what's new on TechCrunch today", "give me a
                      digest of The Verge". A specific source name MUST
                      be present; place it in "sourceName".
- OTHER             : Anything news-related that does not fit above.

Field Rules
-----------
- "sourceName"     : The specific feed/source name mentioned, or "" if
                     none. Required for SUMMARIZE_SOURCE. Optional for
                     LATEST. Must be "" for SUMMARIZE_24H.
- "hoursHint"      : An integer number of hours for the time window, or
                     0 to use the default (24h for SUMMARIZE_24H).
                     Examples: "last 12 hours" -> 12, "this week" -> 168,
                     "today" -> 24, "past 6 hours" -> 6.
- "responseText"   : A short, natural-language acknowledgement to show
                     the user BEFORE the actual result is computed
                     (e.g. "Fetching the latest from BBC..."). Keep it
                     under 12 words. May be "" if no acknowledgement
                     is needed.

Output
------
Respond with JSON ONLY — no markdown fences, no commentary. Exact shape:
{
  "intent": "latest" | "summarize_24h" | "summarize_source" | "other",
  "sourceName": "<string>",
  "hoursHint": <integer>,
  "responseText": "<string>"
}
''';

  @override
  List<String> get tools => const ['groq', 'rss'];

  @override
  AgentContextStorage get contextStorage => AgentContextStorage.none;

  // ===========================================================================
  // Entry point
  // ===========================================================================

  @override
  Future<AgentExecutionResult> execute(ExecutionContext context) async {
    try {
      final parsed = await _classify(context);
      final intent = _normalizeIntent(parsed['intent']);

      switch (intent) {
        case _Intent.latest:
          return _handleLatest(context, parsed);
        case _Intent.summarize24h:
          return _handleSummarize(
            context,
            parsed,
            defaultHours: 24,
            label: 'the last {hours} hours across your feeds',
          );
        case _Intent.summarizeSource:
          return _handleSummarizeSource(context, parsed);
        case _Intent.other:
          return AgentExecutionResult(
            responseText: (parsed['responseText'] as String?)
                    ?.trim()
                    .isNotEmpty ==
                true
                ? parsed['responseText'] as String
                : "I can fetch your latest news or summarize a window of "
                    "recent articles. Try \"latest news\", \"summarize the "
                    "last 24 hours\", or \"summarize BBC\".",
            agentName: name,
            usedTools: const ['groq'],
          );
      }
    } catch (e, st) {
      return AgentExecutionResult(
        responseText: "I ran into a problem handling that news request. Please try again in a moment.",
        agentName: name,
        success: false,
        errorMessage: '$e\n$st',
        usedTools: const ['groq', 'rss'],
      );
    }
  }

  // ===========================================================================
  // Intent Handlers
  // ===========================================================================

  /// Fetches and formats a list of the most recent articles.
  Future<AgentExecutionResult> _handleLatest(
    ExecutionContext context,
    Map<String, dynamic> parsed,
  ) async {
    final sourceName = (parsed['sourceName'] as String? ?? '').trim();

    final fetchResult = await _safeFetch(
      context.userId,
      sourceName: sourceName.isNotEmpty ? sourceName : null,
    );
    if (fetchResult.error != null) {
      return _errorResult(fetchResult.error!, usedTools: const ['rss']);
    }

    var articles = fetchResult.articles;
    if (articles.isEmpty) {
      return AgentExecutionResult(
        responseText: sourceName.isNotEmpty
            ? "$sourceName doesn't have any recent articles right now."
            : "Nothing new right now across your saved sources.",
        agentName: name,
        usedTools: const ['rss'],
      );
    }

    articles = _sortNewestFirst(articles);
    final shown = articles.take(_maxArticlesForLatestList).toList();

    return AgentExecutionResult(
      responseText: _formatArticleList(
        shown,
        totalFound: articles.length,
        heading: sourceName.isNotEmpty ? "Latest from $sourceName" : "Latest across your feeds",
      ),
      agentName: name,
      usedTools: const ['rss'],
    );
  }

  /// Fetches articles across all feeds within a time window and summarizes them.
  Future<AgentExecutionResult> _handleSummarize(
    ExecutionContext context,
    Map<String, dynamic> parsed, {
    required int defaultHours,
    required String label,
  }) async {
    final hours = _resolveHours(parsed, defaultHours: defaultHours);

    final fetchResult = await _safeFetch(context.userId);
    if (fetchResult.error != null) {
      return _errorResult(fetchResult.error!, usedTools: const ['rss']);
    }

    final cutoff = DateTime.now().subtract(Duration(hours: hours));
    final windowed = fetchResult.articles.where((a) {
      // Articles without a parseable pubDate are retained rather than
      // silently dropped. Excluding them would make feeds with
      // inconsistent date formats vanish from the digest.
      if (a.publishedAt == null) return true;
      return a.publishedAt!.isAfter(cutoff);
    }).toList();

    if (windowed.isEmpty) {
      return AgentExecutionResult(
        responseText: "Nothing published across your saved sources in the last $hours hours.",
        agentName: name,
        usedTools: const ['rss'],
      );
    }

    final prepared = _prepareForSummary(windowed);
    return _summarizeArticles(
      prepared,
      label: label.replaceAll('{hours}', '$hours'),
    );
  }

  /// Fetches articles from a specific named source and summarizes them.
  Future<AgentExecutionResult> _handleSummarizeSource(
    ExecutionContext context,
    Map<String, dynamic> parsed,
  ) async {
    final sourceName = (parsed['sourceName'] as String? ?? '').trim();

    if (sourceName.isEmpty) {
      return AgentExecutionResult(
        responseText: "Which source would you like me to summarize? For example: \"summarize BBC\".",
        agentName: name,
        usedTools: const ['groq'],
      );
    }

    final fetchResult = await _safeFetch(context.userId, sourceName: sourceName);
    if (fetchResult.error != null) {
      return _errorResult(fetchResult.error!, usedTools: const ['rss']);
    }

    if (fetchResult.articles.isEmpty) {
      return AgentExecutionResult(
        responseText: "$sourceName doesn't have any recent articles to summarize right now.",
        agentName: name,
        usedTools: const ['rss'],
      );
    }

    final prepared = _prepareForSummary(fetchResult.articles);
    return _summarizeArticles(prepared, label: sourceName);
  }

  // ===========================================================================
  // Fetch & Source Resolution Layer
  // ===========================================================================

  /// Safely executes the fetch pipeline, catching network/DB errors and
  /// converting them into user-friendly [_NewsError] objects.
  Future<_FetchResult> _safeFetch(String userId, {String? sourceName}) async {
    try {
      final sources = await _resolveSources(userId, name: sourceName);
      if (sourceName != null && sources.length == 1) {
        final fetched = await _fetchOne(sources.single);
        return _FetchResult(fetched, null);
      }

      final all = <RssArticle>[];
      for (final source in sources) {
        try {
          all.addAll(await _fetchOne(source));
        } catch (_) {
          // A single feed failing (bad URL, source temporarily down)
          // should not sink the whole aggregate request. Skip and continue.
        }
      }
      return _FetchResult(all, null);
    } on _NoSourcesException {
      return _FetchResult(
        const [],
        _NewsError(message: "You don't have any saved news sources yet — add one from the News tab first."),
      );
    } on _SourceNotFoundException catch (e) {
      return _FetchResult(
        const [],
        _NewsError(message: "I couldn't find a saved source matching \"${e.attemptedName}\" — check the name and try again."),
      );
    } catch (e) {
      return _FetchResult(
        const [],
        _NewsError(message: "I couldn't fetch the news right now — $e", isHardFailure: true, detail: e.toString()),
      );
    }
  }

  /// Resolves the list of sources to query. Merges user-saved Supabase
  /// sources with global defaults. Falls back to defaults if DB is unreachable.
  Future<List<RssFeedSource>> _resolveSources(String userId, {String? name}) async {
    List<RssFeedSource> saved = [];
    try {
      saved = await RssSourceRepository().getSavedSources(userId);
    } catch (_) {
      // Fallback: If Supabase fails, we still want the agent to function
      // using the globally suggested feeds rather than crashing entirely.
    }

    final pool = <RssFeedSource>[
      ...kSuggestedRssFeeds,
      ...saved,
    ];
    if (pool.isEmpty) throw _NoSourcesException();

    if (name == null || name.trim().isEmpty) return pool;

    final lower = name.trim().toLowerCase();
    final matches = pool.where((s) => s.name.toLowerCase().contains(lower)).toList(growable: false);

    if (matches.isEmpty) throw _SourceNotFoundException(name);
    return matches;
  }

  /// Calls the RSS ToolManager to retrieve and parse a single feed.
  Future<List<RssArticle>> _fetchOne(RssFeedSource source) async {
    final result = await ToolManager.instance.executeTool('rss', {
      'feedUrl': source.feedUrl,
      'sourceName': source.name,
    });
    if (result is! List<RssArticle>) {
      throw StateError('RSS tool returned ${result.runtimeType}; expected List<RssArticle>.');
    }
    return result;
  }

  // ===========================================================================
  // Summarization Engine
  // ===========================================================================

  /// Formats the articles and sends them to Groq for summarization.
  Future<AgentExecutionResult> _summarizeArticles(List<RssArticle> articles, {required String label}) async {
    if (articles.isEmpty) {
      return AgentExecutionResult(
        responseText: "Nothing to summarize from $label right now.",
        agentName: name,
        usedTools: const ['rss'],
      );
    }

    final articlesText = articles.map((a) {
      final body = _truncate(a.description ?? '', _maxCharsPerArticleInSummary);
      return <String>[
        'Source: ${a.sourceName}',
        'Title: ${a.title}',
        'Published: ${a.relativeTime}',
        if (body.isNotEmpty) 'Body: $body',
      ].join('\n');
    }).join('\n\n---\n\n');

    final userPrompt = '''
Summarize the following news articles from $label.

Requirements:
1. Lead with the single most important or breaking story.
2. Group related stories into themed clusters (e.g. "Politics", "Tech", "World"). Use a short bold header for each cluster.
3. Within each cluster, write 2-4 concise bullet points. Each bullet should stand alone and convey a concrete fact, not a teaser.
4. Do NOT editorialize, speculate, or add information that is not in the source material.
5. Do NOT introduce the response with "Here is a summary..." — start directly with the first cluster.
6. End with a one-line "Bottom line:" sentence that captures the overall shape of the news in this set.
7. If two articles describe the same event, merge them into one bullet and cite both source names.

Source material:
 $articlesText
''';

    try {
      final raw = await ToolManager.instance.executeTool('groq', {
        'systemPrompt': _summarizerSystemPrompt,
        'message': userPrompt,
        'history': const [],
      });

      final summary = (raw is String ? raw : '').trim();
      if (summary.isEmpty) {
        return AgentExecutionResult(
          responseText: "I pulled the articles from $label but couldn't produce a summary just now. Please try again.",
          agentName: name,
          success: false,
          errorMessage: 'Groq returned an empty summary.',
          usedTools: const ['rss', 'groq'],
        );
      }

      return AgentExecutionResult(
        responseText: summary,
        agentName: name,
        usedTools: const ['rss', 'groq'],
      );
    } catch (e, st) {
      return AgentExecutionResult(
        responseText: "I fetched the articles from $label but hit an error while writing the summary. Please try again.",
        agentName: name,
        success: false,
        errorMessage: '$e\n$st',
        usedTools: const ['rss', 'groq'],
      );
    }
  }

  static const String _summarizerSystemPrompt = '''
You are the News Agent for Mimir AI. You write clean, scannable news
digests from raw RSS article payloads. You are precise, neutral, and
terse. You never invent details. You merge duplicate stories. You
prioritize by editorial importance (breaking > major > routine). You
always structure output as themed clusters of bullets ending with a
single "Bottom line:" sentence.
''';

  // ===========================================================================
  // Article Preparation Utilities
  // ===========================================================================

  /// Prepares articles for summarization by sorting, deduplicating, and capping.
  List<RssArticle> _prepareForSummary(List<RssArticle> articles) {
    final sorted = _sortNewestFirst(articles);

    final seen = <String>{};
    final deduped = <RssArticle>[];
    for (final a in sorted) {
      final key = _normalizeTitle(a.title);
      // Deduplication matters because multiple feeds frequently carry the same wire story.
      if (key.isEmpty || seen.add(key)) {
        deduped.add(a);
      }
      if (deduped.length >= _maxArticlesForSummary) break;
    }
    return deduped;
  }

  /// Sorts articles newest-first based on `publishedAt`.
  List<RssArticle> _sortNewestFirst(List<RssArticle> articles) {
    final copy = List<RssArticle>.of(articles);
    copy.sort((a, b) {
      final aTime = a.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });
    return copy;
  }

  /// Normalizes titles for deduplication (lowercase, remove punctuation).
  String _normalizeTitle(String title) {
    return title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Safely truncates text to a maximum character count without cutting words in half.
  String _truncate(String text, int maxChars) {
    if (text.length <= maxChars) return text;
    final cut = text.substring(0, maxChars);
    final lastSpace = cut.lastIndexOf(' ');
    return '${lastSpace > 0 ? cut.substring(0, lastSpace) : cut}…';
  }

  // ===========================================================================
  // LLM Classification Utilities
  // ===========================================================================

  /// Classifies the user's intent via Groq.
  Future<Map<String, dynamic>> _classify(ExecutionContext context) async {
    final history = context.recentMessages.map((m) => m.toGroqFormat()).toList();

    final raw = await ToolManager.instance.executeTool('groq', {
      'systemPrompt': systemPrompt,
      'message': _buildPrompt(context),
      'history': history,
    });

    final text = raw is String ? raw : '';
    final parsed = _parseJson(text);

    // Coerce types defensively — Groq occasionally returns hoursHint as
    // a string, or omits fields entirely.
    return {
      'intent': parsed['intent']?.toString() ?? 'other',
      'sourceName': parsed['sourceName']?.toString() ?? '',
      'hoursHint': _coerceInt(parsed['hoursHint']) ?? 0,
      'responseText': parsed['responseText']?.toString() ?? '',
    };
  }

  /// Constructs the prompt payload to send to Groq.
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

  /// Robust JSON parser. Strips markdown code fences and extracts the
  /// outermost JSON object to prevent crashes on malformed LLM output.
  Map<String, dynamic> _parseJson(String text) {
    var cleaned = text.trim();
    if (cleaned.startsWith('```')) {
      cleaned = cleaned
          .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
          .replaceFirst(RegExp(r'\s*```$'), '');
    }

    try {
      return jsonDecode(cleaned) as Map<String, dynamic>;
    } catch (_) {
      // Fall through to brace-scanning if standard decode fails.
    }

    try {
      final start = cleaned.indexOf('{');
      final end = cleaned.lastIndexOf('}');
      if (start == -1 || end == -1 || end <= start) return {};
      return jsonDecode(cleaned.substring(start, end + 1)) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  /// Normalizes the intent string into the internal enum.
  _Intent _normalizeIntent(Object? raw) {
    final value = raw?.toString().toLowerCase().trim() ?? '';
    switch (value) {
      case 'latest':
        return _Intent.latest;
      case 'summarize_24h':
      case 'summarize24h':
      case 'summarize-24h':
        return _Intent.summarize24h;
      case 'summarize_source':
      case 'summarizesource':
      case 'summarize-source':
        return _Intent.summarizeSource;
      default:
        return _Intent.other;
    }
  }

  /// Safely converts dynamic LLM JSON values into integers.
  int? _coerceInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  /// Extracts the time window (in hours) from the classified payload.
  int _resolveHours(Map<String, dynamic> parsed, {required int defaultHours}) {
    final hint = parsed['hoursHint'] as int? ?? 0;
    if (hint > 0 && hint <= 24 * 30) return hint; // Sanity cap: 30 days max
    return defaultHours;
  }

  // ===========================================================================
  // Formatting & Error Helpers
  // ===========================================================================

  /// Formats a list of articles into a clean, markdown-formatted string.
  String _formatArticleList(List<RssArticle> shown, {required int totalFound, required String heading}) {
    final buffer = StringBuffer()
      ..writeln('**$heading**${totalFound > shown.length ? ' (showing ${shown.length} of $totalFound)' : ''}')
      ..writeln();
    for (final a in shown) {
      buffer.writeln('- **${a.title}** — ${a.sourceName} (${a.relativeTime})');
    }
    return buffer.toString().trim();
  }

  /// Converts an internal [_NewsError] into an [AgentExecutionResult].
  AgentExecutionResult _errorResult(_NewsError error, {required List<String> usedTools}) {
    return AgentExecutionResult(
      responseText: error.message,
      agentName: name,
      success: !error.isHardFailure,
      errorMessage: error.detail,
      usedTools: usedTools,
    );
  }
}

// =============================================================================
// Internal Types
// =============================================================================

enum _Intent { latest, summarize24h, summarizeSource, other }

class _FetchResult {
  _FetchResult(this.articles, this.error);
  final List<RssArticle> articles;
  final _NewsError? error;
}

class _NewsError {
  _NewsError({required this.message, this.isHardFailure = false, this.detail});
  final String message;
  final bool isHardFailure;
  final String? detail;
}

class _NoSourcesException implements Exception {}

class _SourceNotFoundException implements Exception {
  _SourceNotFoundException(this.attemptedName);
  final String attemptedName;
}