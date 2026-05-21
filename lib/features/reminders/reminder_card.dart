import 'package:flutter/material.dart';

import 'package:murmur/data/models/reminder.dart';

class ReminderCard extends StatelessWidget {
  const ReminderCard({
    super.key,
    required this.reminder,
    required this.onConfirm,
    required this.onDismiss,
    required this.onSnooze,
  });

  final Reminder reminder;
  final VoidCallback onConfirm;
  final VoidCallback onDismiss;
  final VoidCallback onSnooze;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDone = reminder.status == ReminderStatus.confirmed ||
        reminder.status == ReminderStatus.dismissed;

    Color? cardColor;
    switch (reminder.status) {
      case ReminderStatus.confirmed:
        cardColor = theme.colorScheme.primaryContainer.withOpacity(0.3);
      case ReminderStatus.dismissed:
        cardColor = theme.colorScheme.surfaceContainerHighest;
      case ReminderStatus.snoozed:
        cardColor = theme.colorScheme.secondaryContainer.withOpacity(0.3);
      default:
        cardColor = null;
    }

    return Card(
      color: cardColor,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    reminder.task,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Chip(
                  label: Text(
                    reminder.language.toUpperCase(),
                    style: const TextStyle(fontSize: 11),
                  ),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            if (reminder.timeStr != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.access_time, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    reminder.scheduledAt != null
                        ? _formatDateTime(reminder.scheduledAt!)
                        : reminder.timeStr!,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ],
            const SizedBox(height: 6),
            SizedBox(
              height: 4,
              child: LinearProgressIndicator(
                value: reminder.confidence,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
            if (reminder.transcriptSnippet != null) ...[
              const SizedBox(height: 6),
              Text(
                '"${reminder.transcriptSnippet}"',
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontStyle: FontStyle.italic),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: isDone ? null : onDismiss,
                  child: const Text('Dismiss'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: isDone ? null : onSnooze,
                  child: const Text('Snooze 15m'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: isDone ? null : onConfirm,
                  child: const Text('Confirm'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isToday = dt.year == now.year &&
        dt.month == now.month &&
        dt.day == now.day;
    final isTomorrow =
        dt.difference(today).inDays == 1;

    final timeStr =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (isToday) return 'Today at $timeStr';
    if (isTomorrow) return 'Tomorrow at $timeStr';
    return '${dt.day}/${dt.month} at $timeStr';
  }
}
