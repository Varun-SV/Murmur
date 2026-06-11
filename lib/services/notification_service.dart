import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:murmur/core/result.dart';

final notificationServiceProvider =
    Provider<NotificationService>((ref) => NotificationService());

final _log = Logger('NotificationService');

const _channelId = 'murmur_reminders';
const _channelName = 'Reminders';
const _groupKey = 'com.murmur.reminders';

class NotificationService {
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  final StreamController<int> _tapController =
      StreamController<int>.broadcast();
  final StreamController<(int, String)> _actionController =
      StreamController<(int, String)>.broadcast();

  int _pendingCount = 0;

  Stream<int> get tapStream => _tapController.stream;
  Stream<(int, String)> get actionStream => _actionController.stream;

  Future<Result<void>> initialize() async {
    try {
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      final iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
        notificationCategories: [
          DarwinNotificationCategory(
            'reminder',
            actions: [
              DarwinNotificationAction.plain('confirm', 'Confirm'),
              DarwinNotificationAction.plain('dismiss', 'Dismiss'),
            ],
          ),
        ],
      );
      final initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );
      await _notifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          final id = payload != null ? int.tryParse(payload) : null;

          final actionId = response.actionId;
          if (actionId != null &&
              (actionId == 'confirm' || actionId == 'dismiss')) {
            if (id != null) {
              _actionController.add((id, actionId));
            }
          } else {
            if (id != null) {
              _tapController.add(id);
            }
          }
        },
      );

      // Create the Android notification channel (no-op on iOS).
      const channel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        importance: Importance.high,
        playSound: true,
      );
      await _notifications
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
      final androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        importance: Importance.high,
        priority: Priority.high,
        groupKey: _groupKey,
        actions: const [
          AndroidNotificationAction(
            'confirm',
            'Confirm',
            showsUserInterface: false,
          ),
          AndroidNotificationAction(
            'dismiss',
            'Dismiss',
            showsUserInterface: false,
          ),
        ],
      );
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        categoryIdentifier: 'reminder',
      );
      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );
      await _notifications.show(id, 'Reminder', task, details,
          payload: id.toString());

      _pendingCount++;
      if (_pendingCount > 1) {
        await _notifications.show(
          0,
          'Murmur',
          '$_pendingCount reminders pending',
          NotificationDetails(
            android: AndroidNotificationDetails(
              _channelId,
              _channelName,
              groupKey: _groupKey,
              setAsGroupSummary: true,
            ),
          ),
        );
      }

      _log.info('Showed notification #$id: $task');
      return const Ok(null);
    } catch (e, st) {
      _log.severe('showImmediate failed', e, st);
      return Err('Failed to show notification: $e', cause: e as Object);
    }
  }

  Future<void> cancel(int id) async {
    await _notifications.cancel(id);
    if (_pendingCount > 0) _pendingCount--;
  }

  Future<void> cancelAll() async {
    await _notifications.cancelAll();
    _pendingCount = 0;
  }

  void dispose() {
    _tapController.close();
    _actionController.close();
  }
}
