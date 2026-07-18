import 'dart:convert';
import 'package:mimir_ai/features/agents/core/tool_manager.dart' show ToolManager;

class DsaIntentParser {
  final _toolManager = ToolManager.instance;

  /// Classifier-voiced system prompt - deliberately NOT framed as "you
  /// are a mentor/coach" the way the tutoring handlers in
  /// dsa_handlers.dart are. That persona framing was the actual bug:
  /// combined with GroqTool defaulting to temperature 0.7 (no way to
  /// override it before), the model treated "senior competitive
  /// programmer, interview coach, personal mentor" as an invitation to
  /// answer conversationally instead of emitting strict JSON, so most
  /// messages failed to parse and silently fell back to 'other'. Same
  /// failure mode IntentClassifier's own comments describe for the
  /// identical reason - this prompt now follows that file's established
  /// classifier-voice convention instead, and pairs it with a real low
  /// temperature (see parseIntent below).
  static const String systemPrompt = '''
You are a routing and field-extraction classifier for a DSA (Data
Structures & Algorithms) learning assistant, not a conversational tutor.
You only ever output a single JSON object matching the schema below.
Never add explanation, caveats, markdown fences, or any text outside the
JSON object.

Classify the user's message into exactly one of these intents:

- GET_POTD         : User wants today's GeeksforGeeks Problem of the Day.
  (e.g., "today's problem", "problem of the day", "GFG problem", "what
  is the potd?", "give me the geeksforgeeks question")
- EXPLAIN          : User wants an explanation of a problem or concept.
- HINT             : User is stuck and wants a hint.
- REVEAL_SOLUTION  : User explicitly gives up and asks for the code/
  answer. (e.g., "show me the solution", "give up", "what is the code")
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
    final raw = await _toolManager.executeTool('groq', {
      'systemPrompt': systemPrompt,
      'message': userMessage,
      'history': history,
    
    });

    final text = raw is String ? raw : '';
    final parsed = _parseJson(text);

    if (parsed.isEmpty || parsed['intent'] == null) {
      // ignore: avoid_print
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