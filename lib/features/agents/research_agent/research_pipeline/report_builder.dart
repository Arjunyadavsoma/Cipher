import 'package:flutter/foundation.dart';
import '../../core/tool_manager.dart';

class ReportBuilder {
  final _toolManager = ToolManager.instance;

  Future<String> buildReport(String query, List<Map<String, dynamic>> extractedFacts) async {
    final buffer = StringBuffer();
    buffer.writeln("Research Topic: $query\n\n");
    buffer.writeln("Extracted Facts & Information:");
    for (final fact in extractedFacts) {
      buffer.writeln("- ${fact['fact']} (Source: ${fact['source']})");
    }

    final prompt = "Write a comprehensive, objective research report based on the extracted facts. "
        "Use Markdown formatting. The report MUST include the following sections:\n"
        "# Executive Summary\n"
        "# Background & History\n"
        "# Major Achievements & Positive Impact\n"
        "# Criticisms, Controversies & Negative Aspects\n"
        "# Current Status & Legacy\n"
        "Cite sources inline where applicable. Be objective and balanced, covering both the good and the bad.";

    try {
      final response = await _toolManager.executeTool('groq', {
        'systemPrompt': prompt,
        'message': buffer.toString(),
        'temperature': 0.2,
      }) as String;

      return response;
    } catch (e) {
      debugPrint('ReportBuilder failed: $e');
      return "I gathered the information but encountered an error writing the final report. Here are the raw facts:\n\n${buffer.toString()}";
    }
  }
}