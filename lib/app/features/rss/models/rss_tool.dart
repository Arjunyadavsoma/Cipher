import 'package:http/http.dart' as http;
import 'package:cipher_ai/features/agents/models/tool.dart';
import 'package:xml/xml.dart';

import 'package:cipher_ai/app/features/rss/models/rss_article.dart';

class RssTool implements Tool {
  static const String toolName = 'rss_tool';

  @override
  String get name => toolName;

  @override
  Future<dynamic> execute(Map<String, dynamic> input) async {
    return fetchFeed(
      feedUrl: input['feedUrl'] as String,
      sourceName: input['sourceName'] as String,
    );
  }

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
      return _parseRfc822(raw);
    } catch (_) {
      return null;
    }
  }

  DateTime _parseRfc822(String raw) {
    final cleaned = raw.trim();
    final parts = cleaned.split(RegExp(r'\s+'));

    final offset = parts.length >= 6 && parts[0].endsWith(',') ? 1 : 0;

    final day = int.parse(parts[offset]);
    final month = _monthMap[parts[offset + 1]] ?? 1;
    final year = int.parse(parts[offset + 2]);

    final time = parts[offset + 3].split(':');

    return DateTime.utc(
      year,
      month,
      day,
      int.parse(time[0]),
      int.parse(time[1]),
      time.length > 2 ? int.parse(time[2]) : 0,
    );
  }

  static const Map<String, int> _monthMap = {
    'Jan': 1,
    'Feb': 2,
    'Mar': 3,
    'Apr': 4,
    'May': 5,
    'Jun': 6,
    'Jul': 7,
    'Aug': 8,
    'Sep': 9,
    'Oct': 10,
    'Nov': 11,
    'Dec': 12,
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
