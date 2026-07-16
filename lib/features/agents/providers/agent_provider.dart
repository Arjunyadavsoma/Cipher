import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/agent_service.dart';
import '../models/execution_result.dart';

final agentServiceProvider = Provider<AgentService>((ref) {
  return AgentService.instance;
});

/// Convenience provider if you want to trigger a one-off execution via
/// ref.watch/ref.read from a widget. In practice HomeController will more
/// likely call AgentService.instance.processMessage(...) directly, similar
/// to how it currently calls ChatService.
final agentExecutionProvider =
    FutureProvider.family<AgentExecutionResult, Map<String, String>>(
  (ref, params) async {
    final service = ref.read(agentServiceProvider);
    return service.processMessage(
      userId: params['userId']!,
      chatId: params['chatId']!,
      message: params['message']!,
    );
  },
);