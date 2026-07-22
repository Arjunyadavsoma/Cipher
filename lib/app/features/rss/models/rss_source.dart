import 'package:cipher_ai/core/services/supabase/supabase_service.dart';

import '../models/rss_feed_source.dart';

/// Persists the user's saved RSS feed list.
///
/// Uses Supabase (via the existing `SupabaseService` singleton),
/// consistent with `agent_memory_repository.dart` routing
/// general-purpose user data to Supabase rather than Firestore —
/// Firestore in this app is reserved for agent execution logs/stats
/// per `agent_repository.dart`. This is user data, not agent memory,
/// so it goes through its own repository rather than
/// `AgentMemoryRepository`.
///
/// Expects a `rss_sources` table:
///   id          text primary key
///   user_id     text (or uuid, matching your auth model)
///   name        text
///   feed_url    text
///
/// `is_suggestion` is intentionally NOT persisted — suggestions are a
/// constant (`kSuggestedRssFeeds`) merged in at read time, not stored
/// per-user rows.
class RssSourceRepository {
  final _client = SupabaseService.client;

  Future<List<RssFeedSource>> getSavedSources(String userId) async {
    final rows = await _client
        .from('rss_sources')
        .select()
        .eq('user_id', userId);

    return (rows as List)
        .map((row) => RssFeedSource.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> addSource({
    required String userId,
    required RssFeedSource source,
  }) async {
    await _client.from('rss_sources').insert({
      ...source.toMap(),
      'user_id': userId,
    });
  }

  Future<void> removeSource({
    required String userId,
    required String sourceId,
  }) async {
    await _client
        .from('rss_sources')
        .delete()
        .eq('user_id', userId)
        .eq('id', sourceId);
  }
}
