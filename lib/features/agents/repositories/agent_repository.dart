import 'package:cloud_firestore/cloud_firestore.dart';

/// Handles execution logging and usage-stat tracking, per the Firestore
/// schema:
///   users/{uid}/agentExecutions/{executionId}
///   users/{uid}/agents/{agentId}  (executionCount, lastUsedAt)
class AgentRepository {
  AgentRepository._internal();

  static final AgentRepository instance = AgentRepository._internal();

  final _db = FirebaseFirestore.instance;

  Future<void> logExecution({
    required String userId,
    required String agentName,
    required String message,
    required String response,
    required List<String> toolsUsed,
    required Duration duration,
  }) async {
    await _db
        .collection('users')
        .doc(userId)
        .collection('agentExecutions')
        .add({
      'agentName': agentName,
      'message': message,
      'response': response,
      'timestamp': DateTime.now().toIso8601String(),
      'toolsUsed': toolsUsed,
      'durationMs': duration.inMilliseconds,
    });
  }

  Future<void> incrementExecutionCount(String userId, String agentId) async {
    await _db
        .collection('users')
        .doc(userId)
        .collection('agents')
        .doc(agentId)
        .set({
      'executionCount': FieldValue.increment(1),
      'lastUsedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }
}