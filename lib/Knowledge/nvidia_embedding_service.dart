import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class NvidiaEmbeddingService {
  NvidiaEmbeddingService._internal();
  static final NvidiaEmbeddingService instance = NvidiaEmbeddingService._internal();

  // 🔴 PASTE YOUR NEW REGENERATED KEY HERE
  final String _apiKey = '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'; 

  static const String _model = 'nvidia/nemotron-3-embed-1b';
  static const String _url = 'https://integrate.api.nvidia.com/v1/embeddings';

  /// Converts text into a vector embedding.
  Future<List<double>> embed(String text, {bool isQuery = false}) async {
    try {
      final response = await http.post(
        Uri.parse(_url),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'input': [text],
          'model': _model,
          'encoding_format': 'float',
          'truncate': 'NONE', // FIX: Added truncate NONE as per official docs
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final embedding = data['data'][0]['embedding'] as List;
        return embedding.map((e) => (e as num).toDouble()).toList();
      } else {
        debugPrint('❌ NVIDIA API Error ${response.statusCode}: ${response.body}');
        throw Exception('NVIDIA API failed: ${response.body}');
      }
    } catch (e) {
      debugPrint('❌ NvidiaEmbeddingService failed: $e');
      rethrow;
    }
  }
}