import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:murmur/features/reminders/reminders_provider.dart';
import 'package:murmur/features/reminders/reminders_screen.dart';
import 'package:murmur/features/settings/settings_screen.dart';
import 'package:murmur/features/transcript/transcript_screen.dart';
import 'package:murmur/services/notification_service.dart';
import 'package:murmur/services/pipeline_orchestrator.dart';

/// Holds the reminder ID that should be highlighted in the reminders list
/// after the user taps a notification. Null means no active highlight.
final highlightedReminderProvider = StateProvider<int?>((ref) => null);

class MurmurApp extends StatelessWidget {
  const MurmurApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Murmur',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const _MainShell(),
    );
  }
}

class _MainShell extends ConsumerStatefulWidget {
  const _MainShell();

  @override
  ConsumerState<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<_MainShell>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;

  StreamSubscription<int>? _tapSub;
  StreamSubscription<(int, String)>? _actionSub;

  static const _pages = <Widget>[
    RemindersScreen(),
    TranscriptScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final notificationService = ref.read(notificationServiceProvider);

    _tapSub = notificationService.tapStream.listen((reminderId) {
      setState(() {
        _selectedIndex = 0; // reminders tab
      });
      // Store the reminderId for the RemindersScreen to highlight
      ref.read(highlightedReminderProvider.notifier).state = reminderId;
    });

    _actionSub = notificationService.actionStream.listen((event) {
      final (reminderId, actionId) = event;
      final notifier = ref.read(remindersProvider.notifier);
      if (actionId == 'confirm') {
        notifier.confirm(reminderId);
      } else if (actionId == 'dismiss') {
        notifier.dismiss(reminderId);
      }
    });
  }

  @override
  void dispose() {
    _tapSub?.cancel();
    _actionSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final notifier = ref.read(pipelineProvider.notifier);
    switch (state) {
      case AppLifecycleState.paused:
        notifier.pausePipeline();
      case AppLifecycleState.resumed:
        notifier.resumePipeline();
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.notifications_outlined),
            selectedIcon: Icon(Icons.notifications),
            label: 'Reminders',
          ),
          NavigationDestination(
            icon: Icon(Icons.record_voice_over_outlined),
            selectedIcon: Icon(Icons.record_voice_over),
            label: 'Transcripts',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
