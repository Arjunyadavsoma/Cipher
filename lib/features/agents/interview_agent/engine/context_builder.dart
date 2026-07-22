import '../services/firestore_knowledge_service.dart';

class ContextBuilder {
  final FirestoreKnowledgeService _firestore = FirestoreKnowledgeService();

  Future<Map<String, dynamic>> buildContext(String companyName, String query) async {
    String companyId = companyName.toLowerCase().replaceAll(' ', '_');
    
    // Fetch top 15 most frequent questions
    List<Map<String, dynamic>> topQuestions = await _firestore.getTopCodingQuestions(companyId);
    
    // Fetch the sources (resources/links) we scraped
    List<Map<String, dynamic>> sources = await _firestore.getSources(companyId);
    
    return {
      "coding_questions": topQuestions,
      "sources": sources,
    };
  }
}