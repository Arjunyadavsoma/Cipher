class SearchPlanner {
  /// Generates queries, prioritizing categories that have the least data
  List<String> buildQueries(String company, String role, Map<String, int> currentCounts) {
    String c = company.trim();
    String r = role.trim();
    
    List<String> queries = [
      "$c $r interview experience 2024",
      "$c $r interview questions geeksforgeeks",
    ];

    // Smart focusing: If we don't have enough behavioral questions, search for them!
    if (currentCounts['behavioral']! < 10) {
      queries.add("$c $r behavioral interview questions leadership");
      queries.add("$c $r HR round interview questions");
    }
    
    // If we lack system design, search for that
    if (currentCounts['system_design']! < 10) {
      queries.add("$c $r system design interview questions");
      queries.add("$c $r high level design interview rounds");
    }

    // If we need more coding questions
    if (currentCounts['coding']! < 20) {
      queries.add("$c $r leetcode discuss interview");
      queries.add("$c $r online assessment coding questions");
    }

    // Always include a varied fallback
    queries.add("$c $r technical interview round questions 2023");
    
    return queries;
  }
}