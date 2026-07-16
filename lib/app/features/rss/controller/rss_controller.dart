import 'package:flutter/foundation.dart';
import 'package:mimir_ai/app/features/rss/models/rss_source.dart';
import 'package:mimir_ai/app/features/rss/models/rss_tool.dart';
import '../models/rss_article.dart';
import '../models/rss_feed_source.dart';

enum RssLoadState { idle, loading, loaded, error }

/// Owns RSS feed screen state: the source list (suggestions + saved),
/// which source is selected, and the articles for that source.
///
/// Mirrors `HomeController`'s shape — a Riverpod `ChangeNotifier` that
/// the view listens to, with all actual work (fetching, persistence)
/// delegated to a tool/repository rather than done inline, the same
/// way `HomeController.sendMessage()` delegates to
/// `AgentService.processMessage()` instead of calling Groq directly.
class RssController extends ChangeNotifier {
  final RssTool _rssTool;
  final RssSourceRepository _sourceRepository;
  final String userId;

  RssController({
    required this.userId,
    RssTool? rssTool,
    RssSourceRepository? sourceRepository,
  })  : _rssTool = rssTool ?? RssTool(),
        _sourceRepository = sourceRepository ?? RssSourceRepository();

  List<RssFeedSource> _sources = List.of(kSuggestedRssFeeds);
  List<RssFeedSource> get sources => _sources;

  RssFeedSource? _selectedSource;
  RssFeedSource? get selectedSource => _selectedSource;

  List<RssArticle> _articles = [];
  List<RssArticle> get articles => _articles;

  RssLoadState _loadState = RssLoadState.idle;
  RssLoadState get loadState => _loadState;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  /// Call once when the screen mounts. Loads the user's saved feeds
  /// alongside the built-in suggestions — matches
  /// `HomeController`'s pattern of an explicit init step rather than
  /// doing IO in a constructor.
  Future<void> loadSources() async {
    try {
      final saved = await _sourceRepository.getSavedSources(userId);
      _sources = [...kSuggestedRssFeeds, ...saved];
      notifyListeners();
    } catch (_) {
      // Saved-source load failure shouldn't block the screen —
      // suggestions still work. Silently keep the suggestion-only
      // list rather than surfacing an error for a non-critical read.
      _sources = List.of(kSuggestedRssFeeds);
      notifyListeners();
    }
  }

  Future<void> selectSource(RssFeedSource source) async {
    _selectedSource = source;
    _loadState = RssLoadState.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final fetched = await _rssTool.fetchFeed(
        feedUrl: source.feedUrl,
        sourceName: source.name,
      );
      _articles = fetched;
      _loadState = RssLoadState.loaded;
    } catch (e) {
      _articles = [];
      _loadState = RssLoadState.error;
      _errorMessage = e is RssFetchException
          ? e.message
          : 'Couldn\'t load ${source.name}. Check the feed URL and try again.';
    }
    notifyListeners();
  }

  Future<void> addCustomSource({
    required String name,
    required String feedUrl,
  }) async {
    final newSource = RssFeedSource(
      id: 'user-${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      feedUrl: feedUrl,
    );
    _sources = [..._sources, newSource];
    notifyListeners();

    try {
      await _sourceRepository.addSource(userId: userId, source: newSource);
    } catch (_) {
      // Persistence failed but the source still works this session —
      // don't roll back the in-memory add, just leave it unsaved.
      // A production version should surface this via a snackbar;
      // left as a visible gap rather than silently pretending it
      // succeeded.
    }
  }

  Future<void> removeSource(RssFeedSource source) async {
    if (source.isSuggestion) return; // suggestions aren't removable
    _sources = _sources.where((s) => s.id != source.id).toList();
    if (_selectedSource?.id == source.id) {
      _selectedSource = null;
      _articles = [];
      _loadState = RssLoadState.idle;
    }
    notifyListeners();
    await _sourceRepository.removeSource(userId: userId, sourceId: source.id);
  }
}