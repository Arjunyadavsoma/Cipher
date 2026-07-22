class InterviewIntent {
  final bool isInterviewQuery;
  final String? companyName;

  InterviewIntent({required this.isInterviewQuery, this.companyName});
}

class InterviewIntentParser {
  // Keywords that trigger the interview agent
  static const List<String> _triggerKeywords = [
    'interview', 'hiring', 'mock interview', 'placement', 
    'previous year', 'interview experience', 'shortlisted'
  ];

  /// Parses the user query to extract company name and intent
  InterviewIntent parse(String query) {
    String lowerQuery = query.toLowerCase();
    
    // 1. Check if the query is related to interviews
    bool hasTrigger = _triggerKeywords.any((kw) => lowerQuery.contains(kw));
    if (!hasTrigger) {
      return InterviewIntent(isInterviewQuery: false);
    }

    // 2. Extract Company Name (Basic NLP / Keyword matching)
    // You can upgrade this to use a lightweight LLM call later
    List<String> knownCompanies = ['google', 'microsoft', 'amazon', 'meta', 'apple', 'netflix', 'adobe'];
    
    String? extractedCompany;
    for (var company in knownCompanies) {
      if (lowerQuery.contains(company)) {
        extractedCompany = company;
        break;
      }
    }

    // If we found a trigger word and a company, we have an intent
    if (extractedCompany != null) {
      return InterviewIntent(isInterviewQuery: true, companyName: extractedCompany);
    }

    return InterviewIntent(isInterviewQuery: false);
  }
}