import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../features/agents/services/api_key_pool_service.dart';

/// Transcribes voice recordings to text via Groq's Whisper API
/// (audio/transcriptions endpoint - separate from the chat/completions
/// endpoint ChatService uses). Routed through the same ApiKeyPoolService
/// as everything else, so key rotation/rate-limit handling stays
/// consistent across the whole app.
class TranscriptionService {
  TranscriptionService._internal();

  static final TranscriptionService instance = TranscriptionService._internal();

  static const String _baseUrl =
      'https://api.groq.com/openai/v1/audio/transcriptions';

  /// whisper-large-v3-turbo is faster and cheaper than whisper-large-v3
  /// with only a small accuracy tradeoff - good default for voice chat
  /// messages where latency matters more than perfect transcription of,
  /// say, technical jargon.
  static const String _model = 'whisper-large-v3-turbo';

  Future<String> transcribeFile(String localFilePath) async {
    final apiKey = await ApiKeyPoolService.instance.getNextKey();

    try {
      final request = http.MultipartRequest('POST', Uri.parse(_baseUrl))
        ..headers['Authorization'] = 'Bearer $apiKey'
        ..fields['model'] = _model
        ..fields['response_format'] = 'json'
        ..files.add(await http.MultipartFile.fromPath('file', localFilePath));

      final streamedResponse =
          await request.send().timeout(const Duration(seconds: 60));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode != 200) {
        final error = jsonDecode(response.body);
        throw Exception(
          error['error']?['message'] ?? 'Transcription request failed',
        );
      }

      final data = jsonDecode(response.body);
      final text = (data['text'] as String?)?.trim();

      if (text == null || text.isEmpty) {
        throw Exception(
          'No speech detected - the recording may be silent or too short.',
        );
      }

      await ApiKeyPoolService.instance.reportSuccess(apiKey);
      return text;
    } catch (e) {
      await ApiKeyPoolService.instance.reportFailure(apiKey, error: e.toString());
      rethrow;
    }
  }
}