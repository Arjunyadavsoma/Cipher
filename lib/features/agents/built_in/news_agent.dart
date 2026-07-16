import 'dart:convert';

import 'package:mimir_ai/app/features/rss/models/rss_article.dart';
import 'package:mimir_ai/app/features/rss/models/rss_feed_source.dart';
import 'package:mimir_ai/app/features/rss/models/rss_source.dart';

import '../core/base_agent.dart';
import '../core/tool_manager.dart';
import '../models/agent_context_storage.dart';
import '../models/execution_context.dart';
import '../models/execution_result.dart';


/// Handles three things:
///   1. LATEST          - "what's the latest news" -> most recent articles
///                         across every saved feed (or one named source),
///                         listed rather than summarized.
///   2. SUMMARIZE_24H    - "summarize the last 24 hours" -> fetches
///                         articles across all saved feeds published in
///                         the last day, hands them to Groq for a digest.
///   3. SUMMARIZE_SOURCE - "summarize BBC" / "what's new on TechCrunch"
///                         -> same digest treatment, scoped to one named
///                         source instead of every feed.
///
/// IMPORTANT - naming/mention seam (flagged rather than silently
/// resolved): `AgentRouter._findMentionedAgent` matches literal text
/// "@<agent.name>" (lowercased), NOT agent.id. Setting `name` to
/// "Newsagent" (no space) is what makes typing "@newsagent" actually
/// route here - "News Agent" (matching EmailAgent's "Email Agent"
/// display-name convention) would require typing "@news agent" instead,
/// which doesn't match what was asked for. This trades away naming
/// consistency with EmailAgent for a literal, working "@newsagent"
/// mention - revisit if display-name consistency turns out to matter
/// more than the exact mention text.
class NewsAgent implements BaseAgent {
  @override
  String get id => 'news_agent';

  @override
  String get name => 'Newsagent';

  @override
  String get description =>
      'Handles fetching and summarizing news from the user\'s saved RSS '
      'feeds. Use for any request asking for the latest news, a summary '
      'of recent news (e.g. "last 24 hours"), or a digest of a specific '
      'saved news source by name.';

  @override
  String get systemPrompt => '''
You are the News Agent inside Mimir AI. Classify the user's message into
exactly one of these intents:

- LATEST: user wants to see what's newest right now, without asking for
  a written summary - e.g. "latest news", "what's new", "show me recent
  articles". This is a listing request, not a summarization request.
- SUMMARIZE_24H: user wants a written digest/summary covering roughly the
  last day across their feeds in general - e.g. "summarize the last 24
  hours", "catch me up on today's news", "what happened today".
- SUMMARIZE_SOURCE: user wants a digest scoped to ONE specific named
  source - e.g. "summarize BBC", "what's new on TechCrunch today". Only
  use this if a specific source name is actually mentioned.
- OTHER: anything else news-related that doesn't fit the above.

For SUMMARIZE_SOURCE, also extract:
- sourceName: the specific feed/source name mentioned (e.g. "BBC",
  "TechCrunch", "The Verge"), else "" if none is clearly named.

For any intent, also extract:
- hoursHint: a specific timeframe in hours if the user gave one other
  than the implicit "24" default (e.g. "last 12 hours" -> 12, "this
  week" -> 168), else 0 to mean "use the intent's default".

Always respond with JSON only, no other text, in this exact shape:
{
  "intent": "latest" | "summarize_24h" | "summarize_source" | "other",
  "sourceName": "<source name for summarize_source, or empty string>",
  "hoursHint": <integer, 0 for default>,
  "responseText": "<short natural-language message to show the user>"
}
''';

  @override
  List<String> get tools => ['groq', 'rss'];

  @override
  AgentContextStorage get contextStorage => AgentContextStorage.none;

  /// Caps how many articles get sent to Groq for summarization - protects
  /// both token usage and response time if the user has many saved feeds.
  /// Same defensive-cap tradeoff as EmailAgent's `_maxSearchResults`.
  static const _maxArticlesForSummary = 40;

  /// Caps how many articles are listed for a plain LATEST request (no
  /// summarization, so this can be a bit more generous than the
  /// summary cap, but still bounded).
  static const _maxArticlesForLatestList = 15;

  @override
  Future<AgentExecutionResult> execute(ExecutionContext context) async {
    final parsed = await _classify(context);
    final intent = parsed['intent'] as String? ?? 'other';

    switch (intent) {
      case 'latest':
        return _handleLatest(context, parsed);
      case 'summarize_24h':
        return _handleSummarize(context, parsed, defaultHours: 24);
      case 'summarize_source':
        return _handleSummarizeSource(context, parsed);
      default:
        return AgentExecutionResult(
          responseText: parsed['responseText'] as String? ?? '',
          agentName: name,
          usedTools: const ['groq'],
        );
    }
  }

  // ---------- LATEST ----------

  Future<AgentExecutionResult> _handleLatest(
    ExecutionContext context,
    Map<String, dynamic> parsed,
  ) async {
    final sourceName = (parsed['sourceName'] as String? ?? '').trim();

    List<RssArticle> articles;
    try {
      articles = sourceName.isNotEmpty
          ? await _fetchOneSource(context.userId, sourceName)
          : await _fetchAllSavedSources(context.userId);
    } on _NoSourcesException {
      return AgentExecutionResult(
        responseText: "You don't have any saved news sources yet — add "
            "one from the News tab first.",
        agentName: name,
      );
    } on _SourceNotFoundException catch (e) {
      return AgentExecutionResult(
        responseText: "I couldn't find a saved source matching "
            "\"${e.attemptedName}\" — check the name and try again.",
        agentName: name,
      );
    } catch (e) {
      return AgentExecutionResult(
        responseText: "I couldn't fetch the news right now — $e",
        agentName: name,
        success: false,
        errorMessage: e.toString(),
      );
    }

    if (articles.isEmpty) {
      return AgentExecutionResult(
        responseText: sourceName.isNotEmpty
            ? "$sourceName doesn't have any recent articles right now."
            : "Nothing new right now across your saved sources.",
        agentName: name,
        usedTools: const ['rss'],
      );
    }

    articles.sort((a, b) {
      final aTime = a.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.publishedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime); // newest first
    });

    final shown = articles.take(_maxArticlesForLatestList).toList();

    return AgentExecutionResult(
      responseText: _formatArticleList(
        shown,
        totalFound: articles.length,
        heading: sourceName.isNotEmpty
            ? "Latest from $sourceName"
            : "Latest across your feeds",
      ),
      agentName: name,
      usedTools: const ['rss'],
    );
  }

  // ---------- SUMMARIZE (all sources, time-windowed) ----------

  Future<AgentExecutionResult> _handleSummarize(
    ExecutionContext context,
    Map<String, dynamic> parsed, {
    required int defaultHours,
  }) async {
    final hoursHint = parsed['hoursHint'] as int? ?? 0;
    final hours = hoursHint > 0 ? hoursHint : defaultHours;

    List<RssArticle> articles;
    try {
      articles = await _fetchAllSavedSources(context.userId);
    } on _NoSourcesException {
      return AgentExecutionResult(
        responseText: "You don't have any saved news sources yet — add "
            "one from the News tab first.",
        agentName: name,
      );
    } catch (e) {
      return AgentExecutionResult(
        responseText: "I couldn't fetch the news right now — $e",
        agentName: name,
        success: false,
        errorMessage: e.toString(),
      );
    }

    final cutoff = DateTime.now().subtract(Duration(hours: hours));
    final windowed = articles.where((a) {
      // Articles with no parseable pubDate are kept rather than dropped
      // silently - excluding them would mean feeds with inconsistent
      // date formats just vanish from the summary with no indication
      // why, which is worse than including a few undated items.
      if (a.publishedAt == null) return true;
      return a.publishedAt!.isAfter(cutoff);
    }).toList();

    if (windowed.isEmpty) {
      return AgentExecutionResult(
        responseText: "Nothing published across your saved sources in "
            "the last $hours hours.",
        agentName: name,
        usedTools: const ['rss'],
      );
    }

    return _summarizeArticles(
      windowed,
      label: "the last $hours hours across your feeds",
    );
  }

  // ---------- SUMMARIZE (one named source) ----------

  Future<AgentExecutionResult> _handleSummarizeSource(
    ExecutionContext context,
    Map<String, dynamic> parsed,
  ) async {
    final sourceName = (parsed['sourceName'] as String? ?? '').trim();

    if (sourceName.isEmpty) {
      return AgentExecutionResult(
        responseText: "Which source would you like me to summarize?",
        agentName: name,
      );
    }

    List<RssArticle> articles;
    try {
      articles = await _fetchOneSource(context.userId, sourceName);
    } on _SourceNotFoundException catch (e) {
      return AgentExecutionResult(
        responseText: "I couldn't find a saved source matching "
            "\"${e.attemptedName}\" — check the name and try again.",
        agentName: name,
      );
    } catch (e) {
      return AgentExecutionResult(
        responseText: "I couldn't fetch $sourceName right now — $e",
        agentName: name,
        success: false,
        errorMessage: e.toString(),
      );
    }

    if (articles.isEmpty) {
      return AgentExecutionResult(
        responseText: "$sourceName doesn't have any recent articles to "
            "summarize right now.",
        agentName: name,
        usedTools: const ['rss'],
      );
    }

    return _summarizeArticles(articles, label: sourceName);
  }

  // ---------- SHARED: fetch + summarize helpers ----------

  Future<List<RssArticle>> _fetchAllSavedSources(String userId) async {
    final sources = [
      ...kSuggestedRssFeeds,
      ...await RssSourceRepository().getSavedSources(userId),
    ];

    if (sources.isEmpty) throw _NoSourcesException();

    final all = <RssArticle>[];
    for (final source in sources) {
      try {
        final fetched = await ToolManager.instance.executeTool('rss', {
              'feedUrl': source.feedUrl,
              'sourceName': source.name,
            })
            as List<RssArticle>;
        all.addAll(fetched);
      } catch (_) {
        // One feed failing (bad URL, source temporarily down) shouldn't
        // sink the whole aggregate request - same reasoning as
        // RssController.loadSources() treating a saved-source load
        // failure as non-fatal. Skip and continue with the rest.
      }
    }

    return all;
  }

  Future<List<RssArticle>> _fetchOneSource(
    String userId,
    String sourceName,
  ) async {
    final sources = [
      ...kSuggestedRssFeeds,
      ...await RssSourceRepository().getSavedSources(userId),
    ];

    final lowerTarget = sourceName.toLowerCase();
    final match = sources.where(
      (s) => s.name.toLowerCase().contains(lowerTarget),
    );

    if (match.isEmpty) {
      throw _SourceNotFoundException(sourceName);
    }

    final source = match.first;
    return await ToolManager.instance.executeTool('rss', {
          'feedUrl': source.feedUrl,
          'sourceName': source.name,
        })
        as List<RssArticle>;
  }

  Future<AgentExecutionResult> _summarizeArticles(
    List<RssArticle> articles, {
    required String label,
  }) async {
    final capped = articles.take(_maxArticlesForSummary).toList();

    final articlesText = capped
        .map(
          (a) =>
              "Source: ${a.sourceName}\nTitle: ${a.title}\nPublished: "
              "${a.relativeTime}\nSummary: ${a.description}",
        )
        .join('\n\n');

    final summaryPrompt =
        "Summarize these news articles from $label for the user. "
        "Group related stories together, lead with anything major or "
        "breaking, and keep it concise and easy to scan.\n\n$articlesText";

    final summary = await ToolManager.instance.executeTool('groq', {
          'systemPrompt':
              'You are the News Agent. Summarize news articles clearly, '
              'concisely, and without editorializing beyond what the '
              'source material states.',
          'message': summaryPrompt,
          'history': const [],
        }) as String;

    return AgentExecutionResult(
      responseText: summary,
      agentName: name,
      usedTools: const ['rss', 'groq'],
    );
  }

  String _formatArticleList(
    List<RssArticle> shown, {
    required int totalFound,
    required String heading,
  }) {
    final buffer = StringBuffer();
    buffer.writeln("**$heading**"
        "${totalFound > shown.length ? ' (showing ${shown.length} of $totalFound)' : ''}");
    buffer.writeln();
    for (final a in shown) {
      buffer.writeln("- **${a.title}** — ${a.sourceName} (${a.relativeTime})");
    }
    return buffer.toString().trim();
  }

  // ---------- CLASSIFICATION ----------

  Future<Map<String, dynamic>> _classify(ExecutionContext context) async {
    final history =
        context.recentMessages.map((m) => m.toGroqFormat()).toList();

    final rawResponse = await ToolManager.instance.executeTool('groq', {
          'systemPrompt': systemPrompt,
          'message': _buildPrompt(context),
          'history': history,
        }) as String;

    return _parseJson(rawResponse);
  }

  String _buildPrompt(ExecutionContext context) {
    final buffer = StringBuffer();
    if (context.alwaysContext.isNotEmpty) {
      buffer.writeln(context.alwaysContext);
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
      return jsonDecode(text.substring(start, end + 1))
          as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }
}

class _NoSourcesException implements Exception {}

class _SourceNotFoundException implements Exception {
  final String attemptedName;
  _SourceNotFoundException(this.attemptedName);
}
