

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class NvidiaEmbeddingService {
  NvidiaEmbeddingService._internal();
  static final NvidiaEmbeddingService instance = NvidiaEmbeddingService._internal();

  // 🔴 PASTE YOUR NEW REGENERATED KEY HERE
  final String _apiKey = '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'; 


  static const String _model = 'baai/bge-m3';
  static const String _url = 'https://integrate.api.nvidia.com/v1/embeddings';

  /// Converts text into a vector embedding.
  /// [isQuery] should be true for user prompts, false for saved documents.
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
          'input_type': isQuery ? 'query' : 'passage',
          'encoding_format': 'float',
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