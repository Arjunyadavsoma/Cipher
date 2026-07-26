import 'dart:convert';
import 'package:cipher_ai/features/agents/core/tool_manager.dart';

class DsaIntentParser {
  final _toolManager = ToolManager.instance;

  static const String systemPrompt = '''
You are a routing and field-extraction classifier for a DSA (Data
Structures & Algorithms) learning assistant, not a conversational tutor.
You only ever output a single JSON object matching the schema below.
Never add explanation, caveats, markdown fences, or any text outside the
JSON object.

Classify the user's message into exactly one of these intents:

- GET_POTD         : User wants today's GeeksforGeeks Problem of the Day.
- EXPLAIN          : User wants an explanation of a problem or concept.
- HINT             : User is stuck and wants a hint.
- REVEAL_SOLUTION  : User explicitly gives up and asks for the code/answer.
- REVIEW_CODE      : User has pasted code and wants a review.
- COMPLEXITY       : User asks for time/space complexity analysis.
- DRY_RUN          : User wants a step-by-step dry run of code/input.
- SAVE             : User wants to bookmark the current problem.
- LIST_SAVED       : User wants to see saved questions.
- REVISE           : User wants to start revision or be quizzed.
- INTERVIEW_MODE   : User wants to simulate an interview.
- OTHER            : Anything else DSA-related.

Field rules:
- "language"     : The programming language mentioned or detected. Default "Python".
- "code"         : The code block extracted from the user's message, if any. Default "".
- "topic"        : A specific DSA topic mentioned. Default "".
- "responseText" : A short acknowledgement (max 10 words). Default "".

Output JSON only, in this exact shape:
{
  "intent": "get_potd" | "explain" | "hint" | "reveal_solution" | "review_code" | "complexity" | "dry_run" | "save" | "list_saved" | "revise" | "interview_mode" | "other",
  "language": "<string>",
  "code": "<string>",
  "topic": "<string>",
  "responseText": "<string>"
}
''';

  Future<Map<String, dynamic>> parseIntent(
    String userMessage,
    List<Map<String, String>> history,
  ) async {
    // PRO FIX: Explicitly pass temperature: 0.0 to force strict JSON
    final raw = await _toolManager.executeTool('groq', {
      'systemPrompt': systemPrompt,
      'message': userMessage,
      'history': history,
      'temperature': 0.0,
    });

    final text = raw is String ? raw : '';
    final parsed = _parseJson(text);

    if (parsed.isEmpty || parsed['intent'] == null) {
      print('DsaIntentParser: unparseable/empty response: "$text"');
    }

    return parsed;
  }

  Map<String, dynamic> _parseJson(String text) {
    var cleaned = text.trim();
    if (cleaned.startsWith('```')) {
      cleaned = cleaned
          .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
          .replaceFirst(RegExp(r'\s*```$'), '');
    }

    try {
      return jsonDecode(cleaned) as Map<String, dynamic>;
    } catch (_) {}

    try {
      final start = cleaned.indexOf('{');
      final end = cleaned.lastIndexOf('}');
      if (start == -1 || end == -1 || end <= start) return {};
      return jsonDecode(cleaned.substring(start, end + 1)) as Map<String, dynamic>;
    } catch (_) {
      return {'intent': 'other', 'responseText': 'Failed to parse intent.'};
    }
  }
}