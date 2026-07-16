import '../../agents/core/base_agent.dart';
import '../../agents/models/agent_context_storage.dart';
import '../../agents/models/execution_context.dart';
import '../../agents/models/execution_result.dart';
import '../services/pixelster_parser.dart';
import '../services/pixelster_model_selector.dart';
import '../services/pixelster_service.dart';

class ImageAgent implements BaseAgent {
  @override
  String get id => 'pixelster_image';

  @override
  String get name => 'Image Generator';

  @override
  String get description => 'Generates images using Pixelster free API.';

  @override
  String get systemPrompt => 'You are an image generation agent.';

  @override
  List<String> get tools => [];

  @override
  AgentContextStorage get contextStorage => AgentContextStorage.none;

  @override
  Future<AgentExecutionResult> execute(ExecutionContext context) async {
    try {
      final prompt = PixelsterParser.extractPrompt(context.message, '@image');
      final ratio = PixelsterModelSelector.getAspectRatio(prompt);
      
      final url = await PixelsterService.instance.generateImage(
        prompt: prompt,
        ratio: ratio,
      );

      return AgentExecutionResult(
        responseText: '![Generated Image]($url)',
        agentName: name,
        usedTools: const [], 
      );
    } catch (e) {
      return AgentExecutionResult(
        responseText: 'Sorry, I failed to generate the image. Error: $e',
        agentName: name,
        usedTools: const [],
      );
    }
  }
}