import '../../agents/models/execution_context.dart';

/// Lives outside the agents feature per the required architecture -
/// ChatPage/ChatProvider talk to this, and AgentService pulls recent
/// messages from it when building an ExecutionContext.
class ChatAiService {
  ChatAiService._internal();

  static final ChatAiService instance = ChatAiService._internal();

  final Map<String, List<ConversationMessage>> _recentByChatId = {};

  List<ConversationMessage> getRecentMessages(String chatId, {int limit = 4}) {
    final list = _recentByChatId[chatId] ?? [];
    if (list.length <= limit) return list;
    return list.sublist(list.length - limit);
  }

  void addMessage(String chatId, ConversationMessage message) {
    _recentByChatId.putIfAbsent(chatId, () => []).add(message);
  }

  void clearChat(String chatId) {
    _recentByChatId.remove(chatId);
  }
}