import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import 'package:murmur/core/result.dart';
import 'package:murmur/services/notification_service.dart';

final schedulerServiceProvider =
    Provider<SchedulerService>((ref) => SchedulerService());

final _log = Logger('SchedulerService');

// Top-level callback required by android_alarm_manager_plus.
@pragma('vm:entry-point')
Future<void> _alarmCallback(int id) async {
  final prefs = await SharedPreferences.getInstance();
  final task = prefs.getString('alarm_task_$id') ?? 'Reminder';
  await NotificationService().initialize();
  await NotificationService().showImmediate(id, task);
  _log.info('Alarm fired for id=$id task="$task"');
}

class SchedulerService {
  final _iosNotifications = FlutterLocalNotificationsPlugin();

  Future<Result<void>> scheduleReminder(
    int id,
    String task,
    DateTime scheduledAt,
  ) async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        // Android: exact AlarmManager alarm that survives reboots.
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('alarm_task_$id', task);
        await AndroidAlarmManager.oneShotAt(
          scheduledAt,
          id,
          _alarmCallback,
          exact: true,
          wakeup: true,
          rescheduleOnReboot: true,
        );
      } else {
        // iOS: scheduled local notification (approximate timing).
        const iosDetails = DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        );
        await _iosNotifications.zonedSchedule(
          id,
          'Reminder',
          task,
          tz.TZDateTime.from(scheduledAt, tz.local),
          const NotificationDetails(iOS: iosDetails),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
      _log.info('Scheduled reminder #$id for $scheduledAt: "$task"');
      return const Ok(null);
    } catch (e, st) {
      _log.severe('scheduleReminder failed', e, st);
      return Err('Failed to schedule reminder: $e', cause: e as Object);
    }
  }

  Future<Result<void>> cancel(int id) async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        await AndroidAlarmManager.cancel(id);
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('alarm_task_$id');
      } else {
        await _iosNotifications.cancel(id);
      }
      return const Ok(null);
    } catch (e, st) {
      _log.severe('cancel alarm failed', e, st);
      return Err('Failed to cancel alarm: $e', cause: e as Object);
    }
  }
}
