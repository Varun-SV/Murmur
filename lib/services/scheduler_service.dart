import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  Future<Result<void>> scheduleReminder(
    int id,
    String task,
    DateTime scheduledAt,
  ) async {
    try {
      // Store task so the top-level callback can retrieve it (even after reboot).
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
      _log.info('Scheduled alarm #$id for $scheduledAt: "$task"');
      return const Ok(null);
    } catch (e, st) {
      _log.severe('scheduleReminder failed', e, st);
      return Err('Failed to schedule reminder: $e', cause: e as Object);
    }
  }

  Future<Result<void>> cancel(int id) async {
    try {
      await AndroidAlarmManager.cancel(id);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('alarm_task_$id');
      return const Ok(null);
    } catch (e, st) {
      _log.severe('cancel alarm failed', e, st);
      return Err('Failed to cancel alarm: $e', cause: e as Object);
    }
  }
}
