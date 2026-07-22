
import '../models/company_knowledge.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Source; // Hides Firebase's Source enum
class FirestoreKnowledgeService {
  final _db = FirebaseFirestore.instance;

  // Save or Update Company Metadata (Layer 1 & 8)
  Future<void> updateCompanyMetadata(String companyId, CompanyKnowledge master) async {
    await _db.collection('companies').doc(companyId).set({
      'company_name': master.metadata.companyName,
      'last_updated': master.metadata.lastUpdated,
      'confidence': master.metadata.confidence,
      'stats': master.statistics.toJson(),
    }, SetOptions(merge: true));
  }

  // Add a Source (Layer 9)
  Future<void> addSource(String companyId, Source source) async {
    await _db.collection('companies').doc(companyId)
        .collection('sources').doc(source.id)
        .set(source.toJson(), SetOptions(merge: true));
  }

  /// Checks if a question exists by title. If it does, increments frequency.
  /// If not, adds it to Firestore.
  Future<void> mergeCodingQuestion(String companyId, CodingQuestion question, String sourceUrl) async {
    final qRef = _db.collection('companies').doc(companyId).collection('coding_questions');
    
    // Query by title to see if it exists
    final existing = await qRef.where('title', isEqualTo: question.title).limit(1).get();
    
    if (existing.docs.isNotEmpty) {
      // Exists: Increment frequency and add source URL
      final docId = existing.docs.first.id;
      await qRef.doc(docId).update({
        'frequency': FieldValue.increment(1),
        'sources': FieldValue.arrayUnion([sourceUrl]),
        'confidence': question.confidence, // Update confidence
      });
    } else {
      // New: Add the document
      await qRef.doc(question.id).set(question.toJson());
    }
  }

  /// Fetches top coding questions for context building
  Future<List<Map<String, dynamic>>> getTopCodingQuestions(String companyId, {int limit = 15}) async {
    final snapshot = await _db.collection('companies').doc(companyId)
        .collection('coding_questions')
        .orderBy('frequency', descending: true)
        .limit(limit)
        .get();

    return snapshot.docs.map((doc) => doc.data()).toList();
  }




    // Add to firestore_knowledge_service.dart
  
  Future<void> mergeSystemDesign(String companyId, SystemDesign question, String sourceUrl) async {
    final qRef = _db.collection('companies').doc(companyId).collection('system_design');
    final existing = await qRef.where('problem', isEqualTo: question.problem).limit(1).get();
    
    if (existing.docs.isNotEmpty) {
      await qRef.doc(existing.docs.first.id).update({
        'frequency': FieldValue.increment(1),
        'sources': FieldValue.arrayUnion([sourceUrl]),
      });
    } else {
      await qRef.doc(question.id).set(question.toJson());
    }
  }

  Future<void> mergeBehavioral(String companyId, Behavioral question, String sourceUrl) async {
    final qRef = _db.collection('companies').doc(companyId).collection('behavioral');
    final existing = await qRef.where('question', isEqualTo: question.question).limit(1).get();
    
    if (existing.docs.isNotEmpty) {
      await qRef.doc(existing.docs.first.id).update({
        'frequency': FieldValue.increment(1),
        'sources': FieldValue.arrayUnion([sourceUrl]),
      });
    } else {
      await qRef.doc(question.id).set(question.toJson());
    }
  }

  Future<List<Map<String, dynamic>>> getRandomQuestions(String companyId, String type, int limit) async {
    final snapshot = await _db.collection('companies').doc(companyId).collection(type).limit(limit).get();
    return snapshot.docs.map((doc) => doc.data()).toList();
  }
    /// Fetches all URLs that have already been scraped for this company
  Future<Set<String>> getExistingSourceUrls(String companyId) async {
    final snapshot = await _db.collection('companies').doc(companyId).collection('sources').get();
    
    Set<String> urls = {};
    for (var doc in snapshot.docs) {
      String? url = doc.data()['url'] as String?;
      if (url != null) urls.add(url);
    }
    return urls;
    
  }

  /// Fetches the REAL total counts of each category directly from Firestore
  Future<Map<String, int>> getCategoryCounts(String companyId) async {
    try {
      final codingSnap = await _db.collection('companies').doc(companyId).collection('coding_questions').get();
      final systemSnap = await _db.collection('companies').doc(companyId).collection('system_design').get();
      final behavioralSnap = await _db.collection('companies').doc(companyId).collection('behavioral').get();
      final sourcesSnap = await _db.collection('companies').doc(companyId).collection('sources').get();

      return {
        'coding': codingSnap.size,
        'system_design': systemSnap.size,
        'behavioral': behavioralSnap.size,
        'sources': sourcesSnap.size,
      };
    } catch (e) {
      return {'coding': 0, 'system_design': 0, 'behavioral': 0, 'sources': 0};
    }


  }

  Future<List<Map<String, dynamic>>> getSources(String companyId) async {
    final snapshot = await _db.collection('companies').doc(companyId).collection('sources').get();
    return snapshot.docs.map((doc) => doc.data()).toList();
  }

  
}