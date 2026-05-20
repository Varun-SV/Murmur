import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:murmur/core/result.dart';

final notificationServiceProvider =
    Provider<NotificationService>((ref) => NotificationService());

final _log = Logger('NotificationService');

const _channelId = 'murmur_reminders';
const _channelName = 'Reminders';

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<Result<void>> initialize() async {
    try {
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidSettings);
      await _plugin.initialize(initSettings);

      // Create the Android notification channel
      const channel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        importance: Importance.high,
        playSound: true,
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      _log.info('NotificationService initialized');
      return const Ok(null);
    } catch (e, st) {
      _log.severe('NotificationService init failed', e, st);
      return Err('NotificationService init failed: $e', cause: e as Object);
    }
  }

  Future<Result<void>> showImmediate(int id, String task) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        importance: Importance.high,
        priority: Priority.high,
      );
      const details = NotificationDetails(android: androidDetails);
      await _plugin.show(id, 'Reminder', task, details);
      _log.info('Showed notification #$id: $task');
      return const Ok(null);
    } catch (e, st) {
      _log.severe('showImmediate failed', e, st);
      return Err('Failed to show notification: $e', cause: e as Object);
    }
  }

  void cancel(int id) {
    _plugin.cancel(id);
  }
}
