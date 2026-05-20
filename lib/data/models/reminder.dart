import 'package:flutter/foundation.dart';

enum ReminderStatus { pending, confirmed, dismissed, snoozed }

@immutable
class Reminder {
  const Reminder({
    this.id,
    required this.task,
    this.timeStr,
    this.scheduledAt,
    this.speakerId = 'unknown',
    required this.language,
    required this.confidence,
    this.transcriptSnippet,
    this.status = ReminderStatus.pending,
    required this.createdAt,
  });

  final int? id;
  final String task;
  final String? timeStr;
  final DateTime? scheduledAt;
  final String speakerId;
  final String language;
  final double confidence;
  final String? transcriptSnippet;
  final ReminderStatus status;
  final DateTime createdAt;

  factory Reminder.fromMap(Map<String, dynamic> map) {
    final scheduledAtMs = map['scheduled_at'] as int?;
    final statusStr = map['status'] as String? ?? 'pending';
    return Reminder(
      id: map['id'] as int?,
      task: map['task'] as String,
      timeStr: map['time_str'] as String?,
      scheduledAt: scheduledAtMs != null
          ? DateTime.fromMillisecondsSinceEpoch(scheduledAtMs)
          : null,
      speakerId: map['speaker_id'] as String? ?? 'unknown',
      language: map['language'] as String? ?? 'en',
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0.0,
      transcriptSnippet: map['transcript_snippet'] as String?,
      status: ReminderStatus.values.firstWhere(
        (s) => s.name == statusStr,
        orElse: () => ReminderStatus.pending,
      ),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'task': task,
      'time_str': timeStr,
      'scheduled_at': scheduledAt?.millisecondsSinceEpoch,
      'speaker_id': speakerId,
      'language': language,
      'confidence': confidence,
      'transcript_snippet': transcriptSnippet,
      'status': status.name,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }

  Reminder copyWith({
    int? id,
    String? task,
    String? timeStr,
    DateTime? scheduledAt,
    String? speakerId,
    String? language,
    double? confidence,
    String? transcriptSnippet,
    ReminderStatus? status,
    DateTime? createdAt,
  }) {
    return Reminder(
      id: id ?? this.id,
      task: task ?? this.task,
      timeStr: timeStr ?? this.timeStr,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      speakerId: speakerId ?? this.speakerId,
      language: language ?? this.language,
      confidence: confidence ?? this.confidence,
      transcriptSnippet: transcriptSnippet ?? this.transcriptSnippet,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
