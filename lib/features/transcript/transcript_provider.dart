import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

@immutable
class TranscriptEntry {
  const TranscriptEntry({
    required this.text,
    required this.language,
    required this.confidence,
    required this.timestamp,
  });

  final String text;
  final String language; // ISO 639-1
  final double confidence; // [0, 1]
  final DateTime timestamp;
}

class TranscriptNotifier extends Notifier<List<TranscriptEntry>> {
  @override
  List<TranscriptEntry> build() => const [];

  void add(TranscriptEntry entry) => state = [...state, entry];

  void clear() => state = const [];
}

final transcriptProvider =
    NotifierProvider<TranscriptNotifier, List<TranscriptEntry>>(
  TranscriptNotifier.new,
);
