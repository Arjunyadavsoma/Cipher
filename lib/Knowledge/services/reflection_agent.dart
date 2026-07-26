import 'dart:async';
import 'dart:convert';
import 'package:cipher_ai/features/agents/core/tool_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:cipher_ai/Knowledge/knowledge_repository.dart';
import 'package:cipher_ai/Knowledge/knowledge_write_service.dart';

class ReflectionAgent {
  final _repo = KnowledgeRepository.instance;
  final _writeService = KnowledgeWriteService.instance;
  final _toolManager = ToolManager.instance;

  /// Should be run periodically (e.g., once a day at 3 AM).
  /// Finds recent memories, deduplicates them, and merges them.
  Future<void> runNightlyReflection(String userId) async {
    try {
      debugPrint("🧠 ReflectionAgent: Starting nightly reflection...");
      
      // 1. Fetch all memories from the last 7 days
      final recentMemories = await _repo.getRecentFacts(userId, limit: 50);
      if (recentMemories.length < 5) return; // Not enough data to reflect

      // 2. Ask LLM to consolidate the list
      final buffer = StringBuffer();
      buffer.writeln("Here are some recent facts learned about a user:");
      for (int i = 0; i < recentMemories.length; i++) {
        buffer.writeln("${i + 1}. ${recentMemories[i].fact}");
      }


      final response = await _toolManager.executeTool('groq', {
        'systemPrompt': 'You are a memory consolidation engine. Output ONLY a JSON array of strings.',
        'message': buffer.toString(),
        'temperature': 0.0,
      }) as String;

      // 3. Parse consolidated facts
      final start = response.indexOf('[');
      final end = response.lastIndexOf(']');
      if (start == -1 || end == -1) return;

      final List<dynamic> consolidatedList = jsonDecode(response.substring(start, end + 1));
      
      // 4. Delete old memories and save new consolidated ones
      // (In a production system, you might archive the old ones instead of hard deleting)
      for (final memory in recentMemories) {
        await _repo.deleteEntry(userId: userId, entryId: memory.id);
      }

      for (final fact in consolidatedList) {
        await _writeService.saveFacts(userId, [fact.toString()]);
      }

      debugPrint("🧠 ReflectionAgent: Reflection complete. Consolidated ${recentMemories.length} facts into ${consolidatedList.length}.");
    } catch (e) {
      debugPrint("🧠 ReflectionAgent failed: $e");
    }
  }
}