import 'package:flutter/material.dart';

import 'package:murmur/data/models/reminder.dart';

class ReminderCard extends StatelessWidget {
  const ReminderCard({
    super.key,
    required this.reminder,
    required this.onConfirm,
    required this.onDismiss,
  });

  final Reminder reminder;
  final VoidCallback onConfirm;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDone = reminder.status == ReminderStatus.confirmed ||
        reminder.status == ReminderStatus.dismissed;

    Color? cardColor;
    switch (reminder.status) {
      case ReminderStatus.confirmed:
        cardColor = Colors.green.shade50;
      case ReminderStatus.dismissed:
        cardColor = Colors.grey.shade100;
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
                backgroundColor: Colors.grey.shade200,
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
    final isToday = dt.year == now.year &&
        dt.month == now.month &&
        dt.day == now.day;
    final isTomorrow = dt.difference(DateTime(now.year, now.month, now.day)).inDays == 1;

    final timeStr =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (isToday) return 'Today at $timeStr';
    if (isTomorrow) return 'Tomorrow at $timeStr';
    return '${dt.day}/${dt.month} at $timeStr';
  }
}
