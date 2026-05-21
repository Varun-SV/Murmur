import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:murmur/data/models/reminder.dart';
import 'package:murmur/features/reminders/reminder_card.dart';
import 'package:murmur/features/reminders/reminders_provider.dart';

const _snoozeDuration = Duration(minutes: 15);

class RemindersScreen extends ConsumerStatefulWidget {
  const RemindersScreen({super.key});

  @override
  ConsumerState<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends ConsumerState<RemindersScreen> {
  ReminderStatus? _filter; // null = All

  @override
  Widget build(BuildContext context) {
    final asyncReminders = ref.watch(remindersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reminders'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.read(remindersProvider.notifier).refresh(),
          ),
        ],
      ),
      body: Column(
        children: [
          _FilterChips(
            selected: _filter,
            onSelected: (status) => setState(() => _filter = status),
          ),
          Expanded(
            child: asyncReminders.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.red),
                    const SizedBox(height: 12),
                    Text(
                      'Could not load reminders',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      err.toString(),
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () =>
                          ref.read(remindersProvider.notifier).refresh(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (reminders) {
                final filtered = _filter == null
                    ? reminders
                    : reminders
                        .where((r) => r.status == _filter)
                        .toList();

                if (filtered.isEmpty) {
                  return _EmptyState(filter: _filter);
                }

                return ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final reminder = filtered[index];
                    return ReminderCard(
                      reminder: reminder,
                      onConfirm: () => ref
                          .read(remindersProvider.notifier)
                          .confirm(reminder.id!),
                      onDismiss: () => ref
                          .read(remindersProvider.notifier)
                          .dismiss(reminder.id!),
                      onSnooze: () => ref
                          .read(remindersProvider.notifier)
                          .snooze(reminder.id!, _snoozeDuration),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filter});

  final ReminderStatus? filter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (icon, title, subtitle) = switch (filter) {
      ReminderStatus.pending => (
          Icons.notifications_none,
          'No pending reminders',
          'Speak naturally — Murmur will pick up reminder phrases.',
        ),
      ReminderStatus.confirmed => (
          Icons.check_circle_outline,
          'No confirmed reminders',
          'Confirm reminders to track what you\'ve acted on.',
        ),
      ReminderStatus.dismissed => (
          Icons.do_not_disturb_on_outlined,
          'No dismissed reminders',
          'Dismissed reminders will appear here.',
        ),
      ReminderStatus.snoozed => (
          Icons.snooze,
          'No snoozed reminders',
          'Snoozed reminders will reappear in 15 minutes.',
        ),
      null => (
          Icons.notifications_active_outlined,
          'No reminders yet',
          'Start recording and speak naturally.\nMurmur will detect reminder phrases automatically.',
        ),
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: theme.colorScheme.primary.withOpacity(0.4)),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.selected, required this.onSelected});

  final ReminderStatus? selected;
  final void Function(ReminderStatus?) onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          _chip(null, 'All'),
          const SizedBox(width: 8),
          _chip(ReminderStatus.pending, 'Pending'),
          const SizedBox(width: 8),
          _chip(ReminderStatus.confirmed, 'Confirmed'),
          const SizedBox(width: 8),
          _chip(ReminderStatus.dismissed, 'Dismissed'),
          const SizedBox(width: 8),
          _chip(ReminderStatus.snoozed, 'Snoozed'),
        ],
      ),
    );
  }

  Widget _chip(ReminderStatus? status, String label) {
    final isSelected = selected == status;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onSelected(isSelected ? null : status),
    );
  }
}
