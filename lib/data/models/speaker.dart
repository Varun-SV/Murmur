import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

@immutable
class Speaker {
  const Speaker({
    required this.id,
    required this.label,
    required this.firstSeen,
    required this.centroid,
    this.embeddingCount = 1,
  });

  final String id;
  final String label;
  final DateTime firstSeen;
  final Float32List centroid;
  final int embeddingCount;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'label': label,
      'firstSeen': firstSeen.millisecondsSinceEpoch,
      'centroid': base64Encode(centroid.buffer.asUint8List()),
      'embeddingCount': embeddingCount,
    };
  }

  factory Speaker.fromMap(Map<String, dynamic> map) {
    return Speaker(
      id: map['id'] as String,
      label: map['label'] as String,
      firstSeen: DateTime.fromMillisecondsSinceEpoch(map['firstSeen'] as int),
      centroid: Float32List.view(
        base64Decode(map['centroid'] as String).buffer,
      ),
      embeddingCount: map['embeddingCount'] as int? ?? 1,
    );
  }

  Speaker copyWith({
    String? id,
    String? label,
    DateTime? firstSeen,
    Float32List? centroid,
    int? embeddingCount,
  }) {
    return Speaker(
      id: id ?? this.id,
      label: label ?? this.label,
      firstSeen: firstSeen ?? this.firstSeen,
      centroid: centroid ?? this.centroid,
      embeddingCount: embeddingCount ?? this.embeddingCount,
    );
  }
}
