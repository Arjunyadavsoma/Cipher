import 'dart:math';
import 'package:cipher_ai/Knowledge/knowledge_entry.dart';

class ScoringEngine {
  /// Calculates a comprehensive relevance score for a knowledge entry.
  double calculateScore({
    required KnowledgeEntry entry,
    required double semanticScore,
    required bool keywordMatch,
    required int tagMatchCount,
    required String query,
  }) {
    // 1. Semantic Score (0.0 to 1.0) -> Weight 0.45
    final semantic = semanticScore * 0.45;

    // 2. Keyword Match (0 or 1) -> Weight 0.20
    final keyword = keywordMatch ? 1.0 : 0.0;
    final keywordWeighted = keyword * 0.20;

    // 3. Recency (0.0 to 1.0) -> Weight 0.15
    // Decays over 30 days
    final lastAccessed = entry.lastAccessed ?? entry.createdAt;
    final daysSinceAccess = DateTime.now().difference(lastAccessed).inDays;
    final recency = max(0, 1 - (daysSinceAccess / 30));
    final recencyWeighted = recency * 0.15;

    // 4. Importance (0.0 to 1.0) -> Weight 0.10
    final importanceWeighted = entry.importance * 0.10;

    // 5. Access Frequency (Normalized) -> Weight 0.05
    // Normalize access count (e.g., 0 accesses = 0, 10+ accesses = 1.0)
    final accessFreq = (entry.accessCount / 10.0).clamp(0.0, 1.0);
    final accessWeighted = accessFreq * 0.05;

    // 6. Tag Overlap -> Weight 0.05
    final tagScore = (tagMatchCount / 3.0).clamp(0.0, 1.0);
    final tagWeighted = tagScore * 0.05;

    return semantic + keywordWeighted + recencyWeighted + importanceWeighted + accessWeighted + tagWeighted;
  }
}