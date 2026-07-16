import '../../agents/core/base_agent.dart';
import '../../agents/models/agent_context_storage.dart';
import '../../agents/models/execution_context.dart';
import '../../agents/models/execution_result.dart';
import '../services/pixelster_parser.dart';
import '../services/pixelster_model_selector.dart';
import '../services/pixelster_service.dart';

class VideoAgent implements BaseAgent {
  @override
  String get id => 'pixelster_video';

  @override
  String get name => 'Video Generator';

  @override
  String get description => 'Generates videos using Pixelster free API.';

  @override
  String get systemPrompt => 'You are a video generation agent.';

  @override
  List<String> get tools => [];

  @override
  AgentContextStorage get contextStorage => AgentContextStorage.none;

  @override
  Future<AgentExecutionResult> execute(ExecutionContext context) async {
    try {
      final prompt = PixelsterParser.extractPrompt(context.message, '@video');
      final ratio = PixelsterModelSelector.getAspectRatio(prompt);
      
      // This calls the 2-step pipeline: Text -> Image -> Video
      final url = await PixelsterService.instance.generateVideo(
        prompt: prompt,
        ratio: ratio,
      );

      return AgentExecutionResult(
        responseText: 'Here is your generated video: [Watch Video]($url)',
        agentName: name,
        usedTools: const [],
      );
    } catch (e) {
      return AgentExecutionResult(
        responseText: 'Sorry, I failed to generate the video. Error: $e',
        agentName: name,
        usedTools: const [],
      );
    }
  }
}