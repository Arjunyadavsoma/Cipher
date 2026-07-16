/// A single parsed `<item>` from an RSS feed.
class RssArticle {
  final String title;
  final String description;
  final String link;
  final DateTime? publishedAt;
  final String sourceName;
  final String? imageUrl;

  const RssArticle({
    required this.title,
    required this.description,
    required this.link,
    required this.sourceName,
    this.publishedAt,
    this.imageUrl,
  });

  /// Relative time label ("42m ago", "3h ago") to match the Apple
  /// News+ card style — falls back to an em dash when the feed item
  /// had no parseable `pubDate`.
  String get relativeTime {
    if (publishedAt == null) return '—';
    final diff = DateTime.now().difference(publishedAt!);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}