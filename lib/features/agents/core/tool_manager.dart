import 'package:cipher_ai/app/features/rss/models/rss_tool.dart';
import 'package:cipher_ai/core/services/firebase_tool.dart';
import 'package:cipher_ai/core/services/http_tool.dart';
import 'package:cipher_ai/core/services/notification_tool.dart';
import 'package:cipher_ai/features/agents/research_agent/research_tool.dart';

import '../models/tool.dart';
import '../tools/email_tool.dart';
import '../tools/groq_tool.dart';

/// NEW: registers FirebaseTool, HttpTool, and NotificationTool.
///
/// Before this change, DsaAgent's dependencies (DsaRepository,
/// GfgFetchService, DsaNotificationService) all called
/// executeTool('firebase'/'http'/'notification', ...) - none of which
/// were ever registered here. Every one of those calls threw
/// "Tool 'x' not registered", which several call sites caught silently
/// and turned into generic-looking failures ("couldn't be retrieved",
/// fallback responses) - this is the actual reason the DSA agent
/// wasn't working, independent of the earlier intent-classification
/// temperature fix.
class ToolManager {
  ToolManager._internal() {
    registerTool(GroqTool());
    registerTool(EmailTool());
    registerTool(RssTool());
    registerTool(ResearchTool());
    registerTool(FirebaseTool());
    registerTool(HttpTool());
    registerTool(NotificationTool());
  }

  static final ToolManager instance = ToolManager._internal();

  final Map<String, Tool> _tools = {};

  void registerTool(Tool tool) {
    _tools[tool.name] = tool;
  }

  Tool? getTool(String name) => _tools[name];

  Future<dynamic> executeTool(String name, Map<String, dynamic> input) async {
    final tool = _tools[name];

    if (tool == null) {
      throw Exception("Tool '$name' not registered");
    }

    return tool.execute(input);
  }

  List<String> get registeredToolNames => _tools.keys.toList();

  /// Startup self-check: every agent declares the tools it depends on
  /// via BaseAgent.tools. This walks that list against what's actually
  /// registered and returns any mismatches, so a gap like the
  /// firebase/http/notification one above surfaces immediately at
  /// startup (e.g. logged from main.dart) instead of silently failing
  /// the first time a user hits that code path in production.
  List<String> findUnregisteredToolsFor(List<String> declaredTools) {
    return declaredTools.where((t) => !_tools.containsKey(t)).toList();
  }
}
