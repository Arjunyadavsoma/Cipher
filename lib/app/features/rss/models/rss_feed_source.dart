/// A single RSS feed the user has added (or one of the built-in
/// placeholder suggestions shown before they've added their own).
///
/// Mirrors the plain-data-model convention used by `models/agent.dart`
/// and `models/chat_message.dart` elsewhere in the app.
class RssFeedSource {
  final String id;
  final String name;
  final String feedUrl;

  /// True for the built-in placeholder suggestions (BBC, TechCrunch,
  /// The Verge, ...). False once the user has added their own feed.
  /// Kept so the UI can distinguish "starter suggestion" chips from
  /// "your feeds" chips without a second list.
  final bool isSuggestion;

  const RssFeedSource({
    required this.id,
    required this.name,
    required this.feedUrl,
    this.isSuggestion = false,
  });

  factory RssFeedSource.fromMap(Map<String, dynamic> map) {
    return RssFeedSource(
      id: map['id'] as String,
      name: map['name'] as String,
      feedUrl: map['feed_url'] as String,
      isSuggestion: map['is_suggestion'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'feed_url': feedUrl,
      'is_suggestion': isSuggestion,
    };
  }

  RssFeedSource copyWith({String? name, String? feedUrl}) {
    return RssFeedSource(
      id: id,
      name: name ?? this.name,
      feedUrl: feedUrl ?? this.feedUrl,
      isSuggestion: isSuggestion,
    );
  }
}

/// Placeholder starter feeds. Swap these for real ones whenever —
/// nothing else in the feature depends on these specific URLs.
const List<RssFeedSource> kSuggestedRssFeeds = [
  RssFeedSource(
    id: 'suggestion-bbc-news',
    name: 'BBC News',
    feedUrl: 'http://feeds.bbci.co.uk/news/rss.xml',
    isSuggestion: true,
  ),
  RssFeedSource(
    id: 'suggestion-techcrunch',
    name: 'TechCrunch',
    feedUrl: 'https://techcrunch.com/feed/',
    isSuggestion: true,
  ),
  RssFeedSource(
    id: 'suggestion-the-verge',
    name: 'The Verge',
    feedUrl: 'https://www.theverge.com/rss/index.xml',
    isSuggestion: true,
  ),
];