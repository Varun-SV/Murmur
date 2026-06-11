import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'package:murmur/app.dart';
import 'package:murmur/services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  tz.initializeTimeZones();

  if (defaultTargetPlatform == TargetPlatform.android) {
    await AndroidAlarmManager.initialize();
  }

  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((rec) {
    debugPrint('[${rec.level.name}] ${rec.loggerName}: ${rec.message}');
    if (rec.error != null) debugPrint('  error: ${rec.error}');
    if (rec.stackTrace != null) debugPrint('  stack: ${rec.stackTrace}');
  });

  // POST_NOTIFICATIONS permission is requested at runtime by flutter_local_notifications on Android 13+
  await NotificationService().initialize();

  runApp(
    const ProviderScope(
      child: MurmurApp(),
    ),
  );
}
