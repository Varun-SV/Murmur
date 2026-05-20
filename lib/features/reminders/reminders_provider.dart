import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:murmur/data/database/reminder_dao.dart';
import 'package:murmur/data/models/reminder.dart';
import 'package:murmur/services/scheduler_service.dart';

final _log = Logger('RemindersNotifier');

class RemindersNotifier extends AsyncNotifier<List<Reminder>> {
  @override
  Future<List<Reminder>> build() => _load();

  Future<List<Reminder>> _load() async {
    final dao = ref.read(reminderDaoProvider);
    final result = await dao.queryAll();
    return result.fold(
      ok: (list) => list,
      err: (msg) {
        _log.severe('Failed to load reminders: $msg');
        return [];
      },
    );
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_load);
  }

  Future<void> confirm(int id) async {
    final dao = ref.read(reminderDaoProvider);
    await dao.updateStatus(id, ReminderStatus.confirmed);
    await refresh();
  }

  Future<void> dismiss(int id) async {
    final dao = ref.read(reminderDaoProvider);
    await dao.updateStatus(id, ReminderStatus.dismissed);
    ref.read(schedulerServiceProvider).cancel(id);
    await refresh();
  }

  Future<void> snooze(int id, Duration by) async {
    final dao = ref.read(reminderDaoProvider);
    final result = await dao.queryAll();
    final reminder = result.fold(
      ok: (list) => list.where((r) => r.id == id).firstOrNull,
      err: (_) => null,
    );
    if (reminder == null) return;

    final newTime = DateTime.now().add(by);
    await dao.updateStatus(id, ReminderStatus.snoozed);
    await ref
        .read(schedulerServiceProvider)
        .scheduleReminder(id, reminder.task, newTime);
    await refresh();
  }
}

final remindersProvider =
    AsyncNotifierProvider<RemindersNotifier, List<Reminder>>(
        RemindersNotifier.new);
