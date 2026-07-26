import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:cipher_ai/features/agents/models/tool.dart';

class HttpTool implements Tool {
  @override
  String get name => 'http';

  static const Map<String, String> _defaultHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/137.0 Safari/537.36',
    'Accept':
        'text/html,application/json,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9',
    'Cache-Control': 'no-cache',
  };

  @override
  Future<dynamic> execute(Map<String, dynamic> input) async {
    final url = input['url'] as String?;

    if (url == null || url.isEmpty) {
      throw Exception('Missing url');
    }

    final method = (input['method'] ?? 'GET').toString().toUpperCase();

    final headers = {
      ..._defaultHeaders,
      ...(input['headers'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v.toString())),
    };

    final uri = Uri.parse(url);

    late http.Response response;

    switch (method) {
      case 'POST':
        response = await http.post(
          uri,
          headers: headers,
          body: input['body'] is String
              ? input['body']
              : jsonEncode(input['body']),
        );
        break;

      default:
        response = await http.get(
          uri,
          headers: headers,
        );
    }

    if (response.statusCode >= 400) {
      throw Exception(
        'HTTP ${response.statusCode}\n${response.body}',
      );
    }

    return response.body;
  }
}