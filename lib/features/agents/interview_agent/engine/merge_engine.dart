import 'package:uuid/uuid.dart';
import '../models/company_knowledge.dart';

class MergeEngine {
  static const _uuid = Uuid();

  /// Merges an incoming coding question into the master list
  static void mergeCodingQuestion(
    CompanyKnowledge master,
    Map<String, dynamic> incomingData,
    String sourceUrl,
  ) {
    String incomingTitle = incomingData['title']?.toLowerCase().trim() ?? '';
    if (incomingTitle.isEmpty) return;

    // 1. Check if question already exists (Case-insensitive match)
    CodingQuestion? existingQ;
    try {
      existingQ = master.codingQuestions.firstWhere(
        (q) => q.title.toLowerCase().trim() == incomingTitle,
      );
    } catch (e) {
      existingQ = null;
    }

    if (existingQ == null) {
      // 2. If New: Assign ID, Insert, Index
      master.codingQuestions.add(CodingQuestion(
        id: 'q_${_uuid.v4().substring(0, 8)}',
        title: incomingData['title'],
        topic: incomingData['topic'] ?? 'Unknown',
        difficulty: incomingData['difficulty'] ?? 'Medium',
        sources: [sourceUrl],
        confidence: 0.50, // Base confidence
      ));
    } else {
      // 3. If Exists: Increase Frequency, Append Source, Update Confidence
      existingQ.frequency += 1;
      if (!existingQ.sources.contains(sourceUrl)) {
        existingQ.sources.add(sourceUrl);
      }
      // Confidence increases slightly with frequency, max 1.0
      existingQ.confidence = (existingQ.confidence + 0.05).clamp(0.0, 1.0);
    }
  }

    /// Merges an incoming system design question into the master list
  static void mergeSystemDesign(
    CompanyKnowledge master,
    Map<String, dynamic> incomingData,
    String sourceUrl,
  ) {
    String incomingProblem = incomingData['problem']?.toLowerCase().trim() ?? '';
    if (incomingProblem.isEmpty) return;

    SystemDesign? existingQ;
    try {
      existingQ = master.systemDesign.firstWhere(
        (q) => q.problem.toLowerCase().trim() == incomingProblem,
      );
    } catch (e) {
      existingQ = null;
    }

    if (existingQ == null) {
      master.systemDesign.add(SystemDesign(
        id: 'sd_${_uuid.v4().substring(0, 8)}',
        problem: incomingData['problem'],
        difficulty: incomingData['difficulty'] ?? 'Hard',
      ));
    } else {
      existingQ.frequency += 1;
    }
  }

  /// Merges an incoming behavioral question into the master list
  static void mergeBehavioral(
    CompanyKnowledge master,
    Map<String, dynamic> incomingData,
    String sourceUrl,
  ) {
    String incomingQuestion = incomingData['question']?.toLowerCase().trim() ?? '';
    if (incomingQuestion.isEmpty) return;

    Behavioral? existingQ;
    try {
      existingQ = master.behavioral.firstWhere(
        (q) => q.question.toLowerCase().trim() == incomingQuestion,
      );
    } catch (e) {
      existingQ = null;
    }

    if (existingQ == null) {
      master.behavioral.add(Behavioral(
        id: 'b_${_uuid.v4().substring(0, 8)}',
        question: incomingData['question'],
        leadershipPrinciple: incomingData['leadership_principle'] ?? '',
      ));
    } else {
      existingQ.frequency += 1;
    }
  }

  /// Merges a new source into the master list
  static void mergeSource(CompanyKnowledge master, Map<String, dynamic> sourceData) {
    String url = sourceData['url'];
    
    // Only add if URL doesn't already exist
    bool exists = master.sources.any((s) => s.url == url);
    if (!exists) {
      master.sources.add(Source(
        id: 'src_${_uuid.v4().substring(0, 6)}',
        url: url,
        type: sourceData['type'] ?? 'Unknown',
        retrieved: DateTime.now().toIso8601String(),
        quality: sourceData['quality'] ?? 50,
        processed: true,
      ));
    }
  }

  /// Updates the Statistics layer based on current data
  static void updateStatistics(CompanyKnowledge master) {
    master.statistics.coding = master.codingQuestions.length;
    master.statistics.behavioral = master.behavioral.length;
    master.statistics.experiences = master.experiences.length;
    master.statistics.sources = master.sources.length;
    master.statistics.confidence = master.metadata.confidence;
  }
}