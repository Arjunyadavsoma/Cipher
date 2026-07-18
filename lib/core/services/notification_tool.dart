import 'package:mimir_ai/core/services/notification_service.dart';
import 'package:mimir_ai/features/agents/models/tool.dart';

/// Wraps the app's existing NotificationService for agent use.
/// Registered as 'notification'.
///
/// IMPORTANT CAVEAT for 'schedule': NotificationService only exposes
/// showLocalNotification(), which fires immediately - there is no
/// actual time-based scheduling here. DsaNotificationService calls
/// this with type 'schedule' and a scheduledTime ('08:00') expecting a
/// recurring daily reminder, but that request is silently downgraded
/// to "show it right now" below rather than actually scheduling
/// anything for 8 AM. That's a real, separate gap - your codebase
/// already has the correct mechanism for this
/// (BackgroundTaskService.scheduleDailyDsaFetch(), via Workmanager),
/// so DsaNotificationService.scheduleDailyStreakReminder() is
/// currently redundant with it and doing the wrong thing. Route daily
/// reminder scheduling through BackgroundTaskService instead of
/// through this tool's 'schedule' type, or extend this tool with
/// flutter_local_notifications' zonedSchedule() if you want it handled
/// here specifically.
class NotificationTool implements Tool {
  @override
  String get name => 'notification';

  @override
  Future<dynamic> execute(Map<String, dynamic> input) async {
    final type = input['type'] as String? ?? '';

    switch (type) {
      case 'show':
      case 'schedule':
        await NotificationService.showLocalNotification(
          title: input['title'] as String? ?? 'Mimir AI',
          body: input['body'] as String? ?? '',
        );
        return 'shown';
      case 'cancel_all':
        // NotificationService doesn't currently expose a cancel-all
        // method - throwing rather than silently no-op'ing, so a
        // caller relying on this (e.g. "turn off my daily reminders")
        // finds out immediately instead of believing it worked.
        throw UnimplementedError(
          'NotificationTool: cancel_all requested but NotificationService '
          'has no cancellation method yet - add one (e.g. wrapping '
          'FlutterLocalNotificationsPlugin.cancelAll()) before using this.',
        );
      default:
        throw Exception('NotificationTool: unknown operation "$type"');
    }
  }
}