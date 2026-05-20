import 'package:flutter/foundation.dart';

@immutable
class Speaker {
  const Speaker({
    required this.id,
    required this.label,
    required this.firstSeen,
  });

  final String id;
  final String label;
  final DateTime firstSeen;
}
