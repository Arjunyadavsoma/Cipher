import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/agent_context_storage.dart';

/// Reads/writes each agent's persistent context to whichever backend it
/// declares (AgentContextStorage.firestore or .supabase). Agents call
/// through ExecutionContext/AgentExecutor and never touch this directly,
/// so they don't need to know which database backs their memory.
///
/// Both operations report success/failure to the caller rather than
/// swallowing exceptions silently: a caller that can't tell a failed save
/// from a successful one can end up telling the user "Sent!" or "Saved
/// your name" when nothing was actually persisted.
class AgentMemoryRepository {
  AgentMemoryRepository._internal();

  static final AgentMemoryRepository instance =
      AgentMemoryRepository._internal();

  final _db = FirebaseFirestore.instance;
  final _supabase = Supabase.instance.client;

  Future<Map<String, dynamic>?> loadAgentContext({
    required String userId,
    required String agentId,
    required AgentContextStorage storage,
  }) async {
    try {
      switch (storage) {
        case AgentContextStorage.firestore:
          final doc = await _db
              .collection('users')
              .doc(userId)
              .collection('agentContext')
              .doc(agentId)
              .get();
          return doc.data();

        case AgentContextStorage.supabase:
          final row = await _supabase
              .from('agent_context')
              .select()
              .eq('user_id', userId)
              .eq('agent_id', agentId)
              .maybeSingle();
          return row;

        case AgentContextStorage.none:
          return null;
      }
    } catch (e) {
      debugPrint('❌ AgentMemoryRepository.loadAgentContext failed: $e');
      return null;
    }
  }

  /// Returns `true` if the write succeeded, `false` otherwise. Callers
  /// should branch on this rather than assuming success — a swallowed
  /// exception here previously made every agent-side try/catch around a
  /// save unreachable, since this method never surfaced failure.
  Future<bool> saveAgentContext({
    required String userId,
    required String agentId,
    required AgentContextStorage storage,
    required Map<String, dynamic> data,
  }) async {
    try {
      switch (storage) {
        case AgentContextStorage.firestore:
          // Firestore's merge:true means each top-level key in `data` is
          // merged into the existing document — saving `name` alone can
          // never delete `pendingDraft`, and vice versa. Callers do not
          // need to pre-merge or re-send unrelated fields.
          await _db
              .collection('users')
              .doc(userId)
              .collection('agentContext')
              .doc(agentId)
              .set(data, SetOptions(merge: true));
          return true;

        case AgentContextStorage.supabase:
          // Supabase's upsert replaces the row using only the columns
          // supplied — it is NOT a field-level merge the way Firestore's
          // set(merge: true) is. A caller saving only {'name': x} would
          // otherwise silently null out every other column on that row.
          // We read the existing row first and merge client-side so this
          // method has the same "partial save never clobbers the rest"
          // guarantee as the Firestore branch above.
          final existing = await _supabase
              .from('agent_context')
              .select()
              .eq('user_id', userId)
              .eq('agent_id', agentId)
              .maybeSingle();

          final merged = <String, dynamic>{
            ...?existing,
            'user_id': userId,
            'agent_id': agentId,
            ...data,
          };

          await _supabase.from('agent_context').upsert(merged);
          return true;

        case AgentContextStorage.none:
          return true; // no-op storage is not a failure
      }
    } catch (e) {
      debugPrint('❌ AgentMemoryRepository.saveAgentContext failed: $e');
      return false;
    }
  }
}