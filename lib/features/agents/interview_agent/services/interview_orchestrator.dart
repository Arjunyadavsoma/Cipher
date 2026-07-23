import '../models/company_knowledge.dart';

import '../research_pipeline/search_planner.dart';
import '../research_pipeline/search_service.dart';
import '../research_pipeline/content_fetcher.dart';
import '../research_pipeline/information_extractor.dart';
import 'firestore_knowledge_service.dart';

class InterviewOrchestrator {
  final SearchPlanner _planner = SearchPlanner();
  final SearchService _searchService = SearchService();
  final ContentFetcher _fetcher = ContentFetcher();
  final InformationExtractor _extractor = InformationExtractor();
  final FirestoreKnowledgeService _firestore = FirestoreKnowledgeService();

  Future<void> ensureKnowledgeIsFresh(
    String companyName, {
    String role = "SDE",
  }) async {
    final companyId = companyName.toLowerCase().replaceAll(' ', '_');
    CompanyKnowledge master = CompanyKnowledge.empty(companyId, companyName);

    // 1. Fetch REAL current counts from Firestore so we know what's missing
    Map<String, int> currentCounts = await _firestore.getCategoryCounts(
      companyId,
    );
    print("Current DB Counts: $currentCounts");

    // 2. Pass counts to planner to focus on weak areas
    final queries = _planner.buildQueries(companyName, role, currentCounts);

    final visitedUrls = <String>{};
    int urlsProcessed = 0;
    int maxUrlsToProcess = 8;

    // Fetch existing URLs to skip them
    Set<String> existingUrls = await _firestore.getExistingSourceUrls(
      companyId,
    );

    for (final query in queries) {
      if (urlsProcessed >= maxUrlsToProcess) break;

      print("Searching: $query");
      final results = await _searchService.search(query);

      for (final result in results) {
        if (urlsProcessed >= maxUrlsToProcess) break;
        if (visitedUrls.contains(result.url) ||
            existingUrls.contains(result.url))
          continue;

        visitedUrls.add(result.url);
        urlsProcessed++;

        print("Fetching NEW content: ${result.url}");
        final textContent = await _fetcher.fetchAndClean(result.url);
        if (textContent.trim().isEmpty) continue;

        print("Extracting data via LLM...");
        final extractedData = await _extractor.extractInterviewData(
          textContent,
          companyName,
        );

        // Save Source
        final source = Source(
          id: "src_${DateTime.now().millisecondsSinceEpoch}",
          url: result.url,
          type: "Web Search",
          retrieved: DateTime.now().toIso8601String(),
          quality: 70,
        );
        await _firestore.addSource(companyId, source);

                // Merge Coding
        for (final qData in extractedData["coding"] ?? []) {
          final question = CodingQuestion(
            id: "q_${DateTime.now().millisecondsSinceEpoch}_${qData['title'].hashCode}",
            title: qData["title"],
            topic: qData["topic"] ?? "Unknown",
            difficulty: qData["difficulty"] ?? "Medium",
            sources: [result.url],
            imageUrl: qData["image_url"] ?? "", // <-- ADD THIS
          );
          await _firestore.mergeCodingQuestion(companyId, question, result.url);
        }

        // Merge System Design
        for (final qData in extractedData["system_design"] ?? []) {
          final design = SystemDesign(
            id: "sd_${DateTime.now().millisecondsSinceEpoch}_${qData['problem'].hashCode}",
            problem: qData["problem"],
            difficulty: qData["difficulty"] ?? "Hard",
          );
          await _firestore.mergeSystemDesign(companyId, design, result.url);
        }

        // Merge Behavioral
        for (final qData in extractedData["behavioral"] ?? []) {
          final behavioral = Behavioral(
            id: "b_${DateTime.now().millisecondsSinceEpoch}_${qData['question'].hashCode}",
            question: qData["question"],
            leadershipPrinciple: qData["leadership_principle"] ?? "",
          );
          await _firestore.mergeBehavioral(companyId, behavioral, result.url);
        }
      }
    }

    // 3. FIX COUNTING: Fetch the REAL counts AGAIN after merging all new data
    Map<String, int> newCounts = await _firestore.getCategoryCounts(companyId);

    master.statistics.coding = newCounts['coding']!;
    master.statistics.behavioral = newCounts['behavioral']!;
    master.statistics.experiences =
        newCounts['system_design']!; // Map system design to experiences stat if you want, or just use system_design count
    master.statistics.sources = newCounts['sources']!;

    master.metadata.lastUpdated = DateTime.now().toIso8601String();

    int totalQuestions =
        newCounts['coding']! +
        newCounts['system_design']! +
        newCounts['behavioral']!;
    master.metadata.confidence = totalQuestions > 50
        ? 0.95
        : totalQuestions > 20
        ? 0.85
        : 0.70;

    await _firestore.updateCompanyMetadata(companyId, master);

    print(
      "Knowledge pipeline completed for $companyName. Total questions: $totalQuestions",
    );
  }
}
