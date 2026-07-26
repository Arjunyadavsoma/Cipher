import 'dart:convert';
import 'package:cipher_ai/features/agents/DSA_agent/dsa_question.dart';
import 'package:cipher_ai/features/agents/core/tool_manager.dart';
import 'package:cipher_ai/features/agents/interview_agent/research_pipeline/search_service.dart';
 
/// Fetches the GeeksforGeeks Problem of the Day.
///
/// LIMITATION WORTH KNOWING: GFG's POTD hub page
/// (geeksforgeeks.org/problem-of-the-day) is a client-rendered React app.
/// Neither a plain HTTP GET nor a web search can read "today's problem
/// name" from it — that mapping only exists inside GFG's own JavaScript,
/// after the page loads in a real browser. There is no pure-Dart,
/// no-headless-browser way around that specific part.
///
/// So this takes an optional [knownTitle]. If you have it (checked
/// manually, set once a day via remote config, or eventually pulled from a
/// proper backend that can render the page), pass it in and you'll get the
/// real problem with real content. Without it, this makes one best-effort
/// search attempt — which will often come up empty, since same-day content
/// is rarely indexed yet — before falling back to a clearly-labelled
/// generated problem instead of a silently hallucinated "real" one.
class GfgFetchService {
  final _toolManager = ToolManager.instance;
  final _searchService = SearchService();

  Future<DsaQuestion> fetchProblemOfTheDay({String? knownTitle}) async {
    final title = knownTitle ?? await _bestEffortGuessTitle();

    if (title != null && title.isNotEmpty) {
      final result = await _fetchViaSearch(title);
      if (result != null) return result;
    }

    print("Could not resolve a real POTD. Falling back to a generated problem.");
    return _generateFallbackPotd();
  }

  /// Rarely succeeds — same-day POTD titles aren't reliably indexed by web
  /// search yet. Kept as a low-cost attempt rather than skipping straight
  /// to the generated fallback every single time.
  Future<String?> _bestEffortGuessTitle() async {
    final results = await _searchService.search('GeeksforGeeks problem of the day today');
    if (results.isEmpty) return null;
    return results.first.title.isNotEmpty ? results.first.title : null;
  }

  Future<DsaQuestion?> _fetchViaSearch(String title) async {
    try {
      final results = await _searchService.search('$title geeksforgeeks');
      if (results.isEmpty) return null;

      // Prefer a static tutorial/article page over the client-rendered
      // practice judge page (/problems/...) — article pages carry full
      // static content; the judge page only leaks a truncated meta-tag
      // snippet at best.
      final target = results.firstWhere(
        (r) => r.url.contains('geeksforgeeks.org') && !r.url.contains('/problems/'),
        orElse: () => results.firstWhere(
          (r) => r.url.contains('geeksforgeeks.org/problems/'),
          orElse: () => SearchResult(title: '', url: '', content: ''),
        ),
      );
      if (target.url.isEmpty) return null;

      final rawHtml = await _toolManager.executeTool('http', {
        'url': target.url,
      }) as String;

      if (!_looksLikeRealProblem(rawHtml)) return null;

      return _extractViaLlm(rawHtml, target.url);
    } catch (e) {
      print("Search-based fetch failed ($e).");
      return null;
    }
  }

  /// Replaces the old Cloudflare-string check, which never caught the real
  /// failure mode: an empty SPA shell returns HTTP 200 with real-looking
  /// HTML — just none of it about a problem. Genuine problem pages, article
  /// or practice, always mention worked examples; an empty shell never does.
  bool _looksLikeRealProblem(String html) {
    if (html.isEmpty) return false;
    if (html.contains("Just a moment...") || html.contains("cf-browser-verification")) {
      return false;
    }
    final lower = html.toLowerCase();
    return lower.contains('example') && (lower.contains('input') || lower.contains('output'));
  }

  Future<DsaQuestion> _extractViaLlm(String rawHtml, String sourceUrl) async {
    final extractionPrompt =
        "Extract the DSA problem from this GeeksforGeeks HTML. "
        "Return ONLY a valid JSON object with keys: 'title', 'difficulty', 'description', 'url'. "
        "Use an empty string for any field that truly isn't present — never invent a value. "
        "\n\nHTML:\n$rawHtml";

    final llmResponse = await _toolManager.executeTool('groq', {
      'systemPrompt':
          'You are an HTML parser. You only output valid JSON, built only from information present in the HTML. No markdown, no explanation.',
      'message': extractionPrompt,
      'history': const [],
      'temperature': 0.0,
    });

    final cleaned = _extractJson(llmResponse as String);
    final data = jsonDecode(cleaned) as Map<String, dynamic>;

    final title = data['title'] as String?;
    final description = data['description'] as String?;

    return DsaQuestion(
      id: DateTime.now().toUtc().toIso8601String().split('T')[0],
      title: (title != null && title.isNotEmpty) ? title : 'Unknown POTD',
      description:
          (description != null && description.isNotEmpty) ? description : 'No description available.',
      difficulty: (data['difficulty'] as String?)?.isNotEmpty == true ? data['difficulty'] : 'Medium',
      tags: const ['GFG', 'POTD'],
      url: sourceUrl,
    );
  }

  /// Last resort only. Clearly labelled so it's never mistaken for the
  /// actual daily problem — a fabricated problem passed off as real is
  /// worse than an honest "couldn't fetch today's" state.
  Future<DsaQuestion> _generateFallbackPotd() async {
    final today = DateTime.now().toUtc().toIso8601String().split('T')[0];

    final response = await _toolManager.executeTool('groq', {
      'systemPrompt': 'You are a DSA problem generator. Output ONLY valid JSON. No markdown.',
      'message': 'Generate a random Medium or Hard DSA problem suitable for interview prep. '
          'JSON keys must be: "title", "difficulty", "description", "url". '
          'The "url" can just be "https://practice.geeksforgeeks.org/".',
      'temperature': 0.8,
    });

    final cleaned = _extractJson(response as String);
    final data = jsonDecode(cleaned) as Map<String, dynamic>;

    return DsaQuestion(
      id: 'fallback_$today',
      title: '${data['title'] ?? 'Daily Challenge'} (Generated — not official POTD)',
      description: data['description'] ?? 'No description available.',
      difficulty: data['difficulty'] ?? 'Medium',
      tags: const ['Generated', 'Not-Official-POTD'],
      url: data['url'] ?? 'https://practice.geeksforgeeks.org/',
    );
  }

  String _extractJson(String text) {
    var cleaned = text.trim();
    if (cleaned.startsWith('```')) {
      cleaned = cleaned
          .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
          .replaceFirst(RegExp(r'\s*```$'), '');
    }
    final start = cleaned.indexOf('{');
    final end = cleaned.lastIndexOf('}');
    if (start == -1 || end == -1) return '{}';
    return cleaned.substring(start, end + 1);
  }
}