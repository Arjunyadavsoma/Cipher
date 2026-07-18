import 'package:mimir_ai/features/agents/core/tool_manager.dart';
/// Handles scheduling local push notifications for daily reminders.
class DsaNotificationService {
  final _toolManager = ToolManager.instance;

  /// Schedules an 8:00 AM daily notification to keep the streak alive.
  Future<void> scheduleDailyStreakReminder(String userId) async {
    try {
      await _toolManager.executeTool('notification', {
        'type': 'schedule',
        'title': 'DSA Practice Time! 🔥',
        'body': "Today's GeeksforGeeks Problem is ready. Keep your streak alive!",
        'scheduledTime': '08:00',
        'payload': {'screen': 'daily_question'},
      });
    } catch (e) {
      // Silent fail on notification scheduling
    }
  }

  /// Cancels existing notifications (e.g., if user disables reminders).
  Future<void> cancelReminders() async {
    await _toolManager.executeTool('notification', {
      'type': 'cancel_all',
    });
  }
}