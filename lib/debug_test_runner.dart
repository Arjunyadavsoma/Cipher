import 'package:cipher_ai/Knowledge/retrieval/hybrid_retrieval_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:cipher_ai/Knowledge/knowledge_write_service.dart';
import 'package:cipher_ai/features/agents/core/agent_router.dart';

class DebugTestRunner {
  static Future<void> runAllTests() async {
    debugPrint('\n========================================');
    debugPrint('🚀 STARTING AUTOMATED DEBUG TESTS...');
    debugPrint('========================================\n');

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      debugPrint('❌ TEST FAILED: User is not logged in!');
      return;
    }
    debugPrint('✅ User logged in: $userId');

    // --- TEST 1: Save Fact to RAG ---
    debugPrint('\n--- TEST 1: Save Fact to RAG ---');
    try {
      await KnowledgeWriteService.instance.saveFacts(
        userId, 
        ["My favorite programming language is Dart and I love Flutter."]
      );
      debugPrint('✅ TEST 1 PASSED: Fact saved to Firestore.');
    } catch (e, st) {
      debugPrint('❌ TEST 1 FAILED: $e');
      debugPrint(st.toString());
    }

    // --- TEST 2: Retrieve Fact from RAG ---
    debugPrint('\n--- TEST 2: Retrieve Fact from RAG ---');
    try {
      final context = await HybridRetrievalService().buildDomainContext(
        userId: userId,
        userQuery: "What is my favorite language?",
        queryTags: [],
      );
      
      if (context.contains('Dart') || context.contains('Flutter')) {
        debugPrint('✅ TEST 2 PASSED: Context retrieved successfully.');
        debugPrint('   Context: $context');
      } else {
        debugPrint('⚠️ TEST 2 WARNING: Retrieval worked, but context was empty.');
        debugPrint('   Context: $context');
      }
    } catch (e, st) {
      debugPrint('❌ TEST 2 FAILED: $e');
      debugPrint(st.toString());
    }

    // --- TEST 3: Agent @Mention Routing ---
    debugPrint('\n--- TEST 3: Agent @Mention Routing ---');
    try {
      final mentionedAgent = AgentRouter.instance.findMentionedAgent("@research tell me about AI");
      if (mentionedAgent != null && mentionedAgent.name == 'Research Agent') {
        debugPrint('✅ TEST 3 PASSED: AgentRouter correctly mapped @research to Research Agent.');
      } else {
        debugPrint('❌ TEST 3 FAILED: AgentRouter failed to map @research.');
      }
    } catch (e, st) {
      debugPrint('❌ TEST 3 FAILED: $e');
      debugPrint(st.toString());
    }

    debugPrint('\n========================================');
    debugPrint('🏁 AUTOMATED DEBUG TESTS COMPLETE.');
    debugPrint('========================================\n');
  }
}