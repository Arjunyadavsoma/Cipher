import 'package:mimir_ai/app/features/rss/models/rss_tool.dart';
import 'package:mimir_ai/features/agents/research_agent/research_tool.dart';

import '../models/tool.dart';
import '../tools/email_tool.dart';
import '../tools/groq_tool.dart';

class ToolManager {
  ToolManager._internal() {
    registerTool(GroqTool());
    registerTool(EmailTool());
    registerTool(RssTool());
    registerTool(ResearchTool());
  }

  static final ToolManager instance = ToolManager._internal();

  final Map<String, Tool> _tools = {};

  void registerTool(Tool tool) {
    _tools[tool.name] = tool;
  }

  Tool? getTool(String name) => _tools[name];

  Future<dynamic> executeTool(
    String name,
    Map<String, dynamic> input,
  ) async {
    final tool = _tools[name];

    if (tool == null) {
      throw Exception("Tool '$name' not registered");
    }

    return tool.execute(input);
  }

  List<String> get registeredToolNames => _tools.keys.toList();
}