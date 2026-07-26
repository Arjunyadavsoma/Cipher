import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';

class ResearchCacheManager {
  final _db = FirebaseFirestore.instance;

  /// Generates a consistent hash for a query string.
  String _hashQuery(String query) {
    return sha256.convert(utf8.encode(query.toLowerCase().trim())).toString();
  }

  /// Checks if we have cached results for this query.
  Future<List<Map<String, String>>?> getCachedResults(String query) async {
    try {
      final doc = await _db.collection('research_cache').doc(_hashQuery(query)).get();
      if (doc.exists) {
        final data = doc.data()?['results'] as List? ?? [];
        return data.map((e) => Map<String, String>.from(e)).toList();
      }
    } catch (_) {}
    return null;
  }

  /// Saves search results to Firestore to be used later.
  Future<void> cacheResults(String query, List<Map<String, String>> results) async {
    try {
      await _db.collection('research_cache').doc(_hashQuery(query)).set({
        'query': query,
        'results': results,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }
}