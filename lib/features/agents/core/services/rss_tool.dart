import 'package:http/http.dart' as http;
import 'package:mimir_ai/app/features/rss/models/rss_article.dart';
import 'package:mimir_ai/features/agents/models/tool.dart';
import 'package:xml/xml.dart';


/// Wraps RSS feed fetching + XML parsing.
///
/// Follows the same convention as `tools/groq_tool.dart`: nothing else
/// in the app calls `http` directly for RSS — this is the one seam,
/// registered in `ToolManager`, so it stays swappable and testable the
/// same way `GroqTool` wraps Groq access.
///
/// Note: this requires adding the `xml` package to pubspec.yaml
/// (not listed in your current dependency manifest). `http` is
/// already a dependency.
class RssTool implements Tool {
  @override
  String get name => 'rss';

  /// Generic entry point matching `Tool.execute(input)`, the shape
  /// `ToolManager.executeTool('rss', {...})` dispatches to — same
  /// contract `GroqTool`/`EmailTool` satisfy. Thin wrapper only —
  /// `fetchFeed`'s named-param signature below is unchanged and still
  /// what `RssController` calls directly, so that existing caller
  /// isn't affected by this.
  ///
  /// Expects input: {'feedUrl': String, 'sourceName': String}.
  /// Returns List<RssArticle>, same as fetchFeed.
  @override
  Future<List<RssArticle>> execute(Map<String, dynamic> input) {
    return fetchFeed(
      feedUrl: input['feedUrl'] as String,
      sourceName: input['sourceName'] as String,
    );
  }

  /// Fetches and parses a single feed URL into a list of articles.
  /// Throws on network failure or unparseable XML — callers (the
  /// controller) are responsible for catching and surfacing a
  /// user-facing error state, matching how `RssController` handles
  /// `GroqService` failures.
  Future<List<RssArticle>> fetchFeed({
    required String feedUrl,
    required String sourceName,
  }) async {
    final response = await http.get(Uri.parse(feedUrl));

    if (response.statusCode != 200) {
      throw RssFetchException(
        'Failed to load $sourceName (HTTP ${response.statusCode})',
      );
    }

    final document = XmlDocument.parse(response.body);
    final items = document.findAllElements('item');

    return items.map((item) {
      final title = _text(item, 'title') ?? 'Untitled';
      final description = _stripHtml(_text(item, 'description') ?? '');
      final link = _text(item, 'link') ?? '';
      final pubDateRaw = _text(item, 'pubDate');
      final imageUrl = _extractImage(item);

      return RssArticle(
        title: title,
        description: description,
        link: link,
        sourceName: sourceName,
        publishedAt: _parseDate(pubDateRaw),
        imageUrl: imageUrl,
      );
    }).toList();
  }

  String? _text(XmlElement item, String tag) {
    final matches = item.findElements(tag);
    if (matches.isEmpty) return null;
    return matches.first.innerText.trim();
  }

  /// Most feeds put a thumbnail in `<media:content>` or
  /// `<enclosure url="...">`. Falls back to null — the UI handles a
  /// missing image with a plain text-only card rather than a broken
  /// image icon.
  String? _extractImage(XmlElement item) {
    final media = item.findElements('media:content');
    if (media.isNotEmpty) {
      final url = media.first.getAttribute('url');
      if (url != null) return url;
    }
    final enclosure = item.findElements('enclosure');
    if (enclosure.isNotEmpty) {
      final url = enclosure.first.getAttribute('url');
      if (url != null) return url;
    }
    return null;
  }

  DateTime? _parseDate(String? raw) {
    if (raw == null) return null;
    try {
      // RFC 822 format ("Tue, 15 Jul 2026 09:41:00 GMT") isn't
      // directly parseable by DateTime.parse, but HttpDate handles
      // it — imported lazily to keep this file's top-level imports
      // minimal for callers that don't need it.
      return _parseRfc822(raw);
    } catch (_) {
      return null;
    }
  }

  DateTime _parseRfc822(String raw) {
    // Lightweight RFC 822 parser to avoid pulling in a full HTTP date
    // package for one field. Handles the common "Day, DD Mon YYYY
    // HH:MM:SS ZONE" shape most feeds emit.
    final cleaned = raw.trim();
    final parts = cleaned.split(RegExp(r'\s+'));
    // Expect: [Tue,] DD Mon YYYY HH:MM:SS ZONE
    final offset = parts.length >= 6 && parts[0].endsWith(',') ? 1 : 0;
    final day = int.parse(parts[offset]);
    final month = _monthMap[parts[offset + 1]] ?? 1;
    final year = int.parse(parts[offset + 2]);
    final timeParts = parts[offset + 3].split(':');
    final hour = int.parse(timeParts[0]);
    final minute = int.parse(timeParts[1]);
    final second = timeParts.length > 2 ? int.parse(timeParts[2]) : 0;
    return DateTime.utc(year, month, day, hour, minute, second);
  }

  static const Map<String, int> _monthMap = {
    'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
    'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
  };

  String _stripHtml(String input) {
    return input.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }
}

class RssFetchException implements Exception {
  final String message;
  RssFetchException(this.message);

  @override
  String toString() => message;
}