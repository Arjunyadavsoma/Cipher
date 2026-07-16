import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/services/groq/chat_service.dart';

/// Handles token-saving context management:
/// - keeps a rolling, compressed summary of the conversation instead of
///   sending full raw history every turn
/// - builds the small "always context" block (saved memories) sent with
///   every request regardless of which agent runs
/// - detects and saves explicit "remember this" style requests
class ContextSummarizerService {
  ContextSummarizerService._internal();

  static final ContextSummarizerService instance =
      ContextSummarizerService._internal();

  final _db = FirebaseFirestore.instance;

  Future<String> getRollingSummary(String userId, String chatId) async {
    final doc = await _db
        .collection('users')
        .doc(userId)
        .collection('conversationSummary')
        .doc(chatId)
        .get();

    return doc.data()?['summary'] ?? '';
  }

  /// Re-summarizes after every exchange. The new summary REPLACES the old
  /// one (not appended) so it stays bounded in size regardless of how long
  /// the conversation runs.
  Future<void> updateSummary({
    required String userId,
    required String chatId,
    required String previousSummary,
    required String userMessage,
    required String assistantResponse,
  }) async {
    final prompt = "Update this conversation summary in 2-4 concise "
        "sentences, incorporating the new exchange. Keep only the "
        "important facts, decisions, and context needed for future "
        "replies.\n\n"
        "Previous summary: $previousSummary\n\n"
        "New exchange:\nUser: $userMessage\nAssistant: $assistantResponse\n\n"
        "Return only the updated summary text, nothing else.";

    final newSummary = await ChatService.instance.sendMessage(
      message: prompt,
      history: const [],
    );

    await _db
        .collection('users')
        .doc(userId)
        .collection('conversationSummary')
        .doc(chatId)
        .set({
      'summary': newSummary.trim(),
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  /// Builds the small block of always-included context - saved memories
  /// capped at the most recent 15 entries to keep token usage predictable.
  Future<String> buildAlwaysContext(String userId) async {
    final memorySnapshot = await _db
        .collection('users')
        .doc(userId)
        .collection('memory')
        .orderBy('createdAt', descending: true)
        .limit(15)
        .get();

    if (memorySnapshot.docs.isEmpty) return '';

    final facts =
        memorySnapshot.docs.map((d) => "- ${d.data()['fact']}").join('\n');
    return "Known facts about the user:\n$facts";
  }

  bool isMemoryTrigger(String message) {
    final lower = message.toLowerCase();
    return lower.contains('remember that') ||
        lower.contains("don't forget") ||
        lower.contains('keep in mind') ||
        lower.contains('remember this');
  }

  Future<void> saveMemory(String userId, String fact) async {
    await _db.collection('users').doc(userId).collection('memory').add({
      'fact': fact,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }
}