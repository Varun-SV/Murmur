import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:murmur/data/models/reminder.dart';
import 'package:murmur/features/reminders/reminder_card.dart';
import 'package:murmur/features/reminders/reminders_provider.dart';

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
                    Text('Error: $err'),
                    TextButton(
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
                  return const Center(child: Text('No reminders'));
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
