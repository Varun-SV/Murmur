import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:murmur/app.dart';

void main() {
  // Route all Logger output to Flutter's debugPrint so it appears in logcat
  // with the tag "flutter". Use adb logcat -s flutter to filter.
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((rec) {
    debugPrint('[${rec.level.name}] ${rec.loggerName}: ${rec.message}');
    if (rec.error != null) debugPrint('  error: ${rec.error}');
    if (rec.stackTrace != null) debugPrint('  stack: ${rec.stackTrace}');
  });

  runApp(
    const ProviderScope(
      child: MurmurApp(),
    ),
  );
}
