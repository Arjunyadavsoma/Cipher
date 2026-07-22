import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cipher_ai/features/agents/services/api_key_pool_service.dart';

class InformationExtractor {
  final ApiKeyPoolService _apiKeyPool = ApiKeyPoolService.instance;

  /// Sends text to Groq LLM and returns a Map containing coding, system_design, and behavioral questions
  Future<Map<String, dynamic>> extractInterviewData(
    String textContent,
    String company,
  ) async {
    if (textContent.isEmpty) return {};

    try {
      final String apiKey = await _apiKeyPool.getNextKey();

      final response = await http.post(
        Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': 'llama-3.1-8b-instant',
          'messages': [
            {
              'role': 'system',
              'content':
                  'You are an expert data extraction API. Read the text and extract interview questions. If a question requires analyzing an image (like a tree, graph, or matrix), include the image URL in the "image_url" field. Output ONLY a valid JSON object.\nFormat:\n{\n  "coding": [{"title": "Q Name", "topic": "Topic", "difficulty": "Medium", "image_url": "https://..."}],\n  "system_design": [{"problem": "Design X", "difficulty": "Hard", "image_url": ""}],\n  "behavioral": [{"question": "Tell me about Y", "leadership_principle": "Ownership", "image_url": ""}]\n}\nIf no image is needed, leave "image_url" as an empty string "".',
            },
            {
              'role': 'user',
              'content': 'Company: $company\n\nText:\n$textContent',
            },
          ],
          'temperature': 0.1,
        }),
      );

      if (response.statusCode == 429 || response.statusCode == 401) {
        await _apiKeyPool.reportFailure(apiKey, error: response.body);
        print('Groq Key failed/pool updated. Retrying on next cycle.');
        return {};
      }

      if (response.statusCode != 200) {
        print('Groq Extraction failed: ${response.body}');
        return {};
      }

      await _apiKeyPool.reportSuccess(apiKey);

      final data = jsonDecode(response.body);
      String llmOutput = data['choices'][0]['message']['content'].trim();

      // Clean up markdown if LLM ignored instructions
      if (llmOutput.contains('```json')) {
        llmOutput = llmOutput.split('```json')[1].split('```')[0].trim();
      } else if (llmOutput.contains('```')) {
        llmOutput = llmOutput.split('```')[1].split('```')[0].trim();
      }

      final decodedJson = jsonDecode(llmOutput);

      // Ensure it returns a Map
      if (decodedJson is Map<String, dynamic>) {
        return decodedJson;
      }

      return {};
    } catch (e) {
      print('InformationExtractor Error: $e');
      return {};
    }
  }
}
