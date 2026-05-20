import 'package:flutter_test/flutter_test.dart';

import 'package:murmur/core/nlp/time_parser.dart';

void main() {
  // Fixed reference: Wednesday 2026-05-20 14:00:00
  final now = DateTime(2026, 5, 20, 14, 0, 0);

  DateTime? parse(String s) => TimeParser.parse(s, now: now);

  group('relative durations', () {
    test('in 30 minutes', () {
      expect(parse('in 30 minutes'), equals(DateTime(2026, 5, 20, 14, 30)));
    });

    test('in 2 hours', () {
      expect(parse('in 2 hours'), equals(DateTime(2026, 5, 20, 16, 0)));
    });

    test('in 1 minute', () {
      expect(parse('in 1 minute'), equals(DateTime(2026, 5, 20, 14, 1)));
    });
  });

  group('"at" time — advances to tomorrow when past', () {
    test('at 3pm — future today', () {
      expect(parse('at 3pm'), equals(DateTime(2026, 5, 20, 15, 0)));
    });

    test('at 10am — already past → tomorrow', () {
      expect(parse('at 10am'), equals(DateTime(2026, 5, 21, 10, 0)));
    });

    test('at 3:45 pm', () {
      expect(parse('at 3:45 pm'), equals(DateTime(2026, 5, 20, 15, 45)));
    });

    test('at 14:00 — exact now → tomorrow', () {
      // 14:00 == now, so not after → advance
      expect(parse('at 14:00'), equals(DateTime(2026, 5, 21, 14, 0)));
    });
  });

  group('"today at" — never advances', () {
    test('today at 5pm', () {
      expect(parse('today at 5pm'), equals(DateTime(2026, 5, 20, 17, 0)));
    });

    test('today at 10am — past, stays today', () {
      expect(parse('today at 10am'), equals(DateTime(2026, 5, 20, 10, 0)));
    });
  });

  group('"tomorrow at"', () {
    test('tomorrow at 9am', () {
      expect(parse('tomorrow at 9am'), equals(DateTime(2026, 5, 21, 9, 0)));
    });
  });

  group('"next <weekday>"', () {
    test('next monday — from Wed May 20 → Mon May 25', () {
      expect(parse('next monday'), equals(DateTime(2026, 5, 25)));
    });

    test('next wednesday — skips today, goes to next week', () {
      // today is Wednesday; "next wednesday" should skip to May 27
      expect(parse('next wednesday'), equals(DateTime(2026, 5, 27)));
    });
  });

  group('"on <weekday> at"', () {
    test('on friday at 2:30pm — next Friday from Wed = May 22', () {
      expect(
          parse('on friday at 2:30pm'), equals(DateTime(2026, 5, 22, 14, 30)));
    });
  });

  group('unrecognized', () {
    test('empty string returns null', () {
      expect(parse(''), isNull);
    });

    test('sometime soon returns null', () {
      expect(parse('sometime soon'), isNull);
    });

    test('garbage returns null', () {
      expect(parse('ajsdhkasjdhk'), isNull);
    });
  });
}
