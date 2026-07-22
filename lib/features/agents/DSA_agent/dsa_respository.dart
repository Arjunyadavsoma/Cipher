import 'package:cipher_ai/features/agents/DSA_agent/dsa_question.dart';
import 'package:cipher_ai/features/agents/DSA_agent/dsa_user_progress.dart';
import 'package:cipher_ai/features/agents/core/tool_manager.dart';

/// Abstract interface for DSA data persistence.
abstract class DsaRepository {
  Future<DsaQuestion?> getTodaysQuestion();
  Future<void> cacheDailyQuestion(DsaQuestion q);
  Future<void> saveQuestionForUser(String userId, DsaQuestion q);
  Future<List<DsaQuestion>> getSavedQuestions(String userId);
  Future<DsaUserProgress> getUserProgress(String userId);
  Future<void> updateUserProgress(String userId, DsaUserProgress progress);
}

/// Firebase/Firestore implementation of [DsaRepository].
class FirebaseDsaRepository implements DsaRepository {
  final _toolManager = ToolManager.instance;

  @override
  Future<DsaQuestion?> getTodaysQuestion() async {
    try {
      final String today = DateTime.now().toUtc().toIso8601String().split(
        'T',
      )[0];
      final res = await _toolManager.executeTool('firebase', {
        'type': 'get',
        'path': 'daily_questions/$today',
      });

      if (res is Map<String, dynamic> && res.isNotEmpty) {
        return DsaQuestion.fromMap(res);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  @override
  Future<void> cacheDailyQuestion(DsaQuestion q) async {
    final String today = DateTime.now().toUtc().toIso8601String().split('T')[0];
    await _toolManager.executeTool('firebase', {
      'type': 'set',
      'path': 'daily_questions/$today',
      'data': q.toMap(),
    });
  }

  @override
  Future<void> saveQuestionForUser(String userId, DsaQuestion q) async {
    await _toolManager.executeTool('firebase', {
      'type': 'set',
      'path': 'users/$userId/savedQuestions/${q.id}',
      'data': q.toMap(),
    });
  }

  @override
  Future<List<DsaQuestion>> getSavedQuestions(String userId) async {
    final res = await _toolManager.executeTool('firebase', {
      'type': 'collection',
      'path': 'users/$userId/savedQuestions',
    });

    if (res is List) {
      return res
          .map((e) => DsaQuestion.fromMap(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  @override
  Future<DsaUserProgress> getUserProgress(String userId) async {
    // 'users/$userId/statistics' is a 3-segment path - Firestore reads
    // that as a COLLECTION reference, not a document, since document
    // paths must have an even number of segments. FirebaseTool's
    // 'get'/'set' operations call _db.doc(path), which throws an
    // ArgumentError on an odd-segment path. Fixed to a proper 4-segment
    // document path below.
    final res = await _toolManager.executeTool('firebase', {
      'type': 'get',
      'path': 'users/$userId/statistics/progress',
    });
    if (res is Map<String, dynamic>) {
      return DsaUserProgress.fromMap(res);
    }
    return DsaUserProgress();
  }

  @override
  Future<void> updateUserProgress(
    String userId,
    DsaUserProgress progress,
  ) async {
    await _toolManager.executeTool('firebase', {
      'type': 'set',
      'path': 'users/$userId/statistics/progress',
      'data': progress.toMap(),
    });
  }
}
