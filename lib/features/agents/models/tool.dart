/// Every capability an agent can use (LLM calls, web search, sending email,
/// etc.) is wrapped behind this interface. Agents never call an external
/// API directly - they always go through a registered [Tool] via the
/// ToolManager.
abstract class Tool {

  String get name;
 

  Future<dynamic> execute(Map<String, dynamic> input);
}