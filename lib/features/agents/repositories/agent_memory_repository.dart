import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/agent_context_storage.dart';

/// Reads/writes each agent's persistent context to whichever backend it
/// declares (AgentContextStorage.firestore or .supabase). Agents call
/// through ExecutionContext/AgentExecutor and never touch this directly,
/// so they don't need to know which database backs their memory.
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
  }

  Future<void> saveAgentContext({
    required String userId,
    required String agentId,
    required AgentContextStorage storage,
    required Map<String, dynamic> data,
  }) async {
    switch (storage) {
      case AgentContextStorage.firestore:
        await _db
            .collection('users')
            .doc(userId)
            .collection('agentContext')
            .doc(agentId)
            .set(data, SetOptions(merge: true));
        return;

      case AgentContextStorage.supabase:
        await _supabase.from('agent_context').upsert({
          'user_id': userId,
          'agent_id': agentId,
          ...data,
        });
        return;

      case AgentContextStorage.none:
        return;
    }
  }
}