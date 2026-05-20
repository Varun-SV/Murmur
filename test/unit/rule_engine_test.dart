import 'package:flutter_test/flutter_test.dart';

import 'package:murmur/core/nlp/rule_engine.dart';

const _testPatternsJson = '''
{
  "en": [
    {
      "pattern": "remind(?:er)?(?:\\\\s+me)?\\\\s+to\\\\s+(.+?)(?:\\\\s+(?:at|by|on|tomorrow|today|in)\\\\s+(.+?))?\\\\s*\$",
      "taskGroup": 1,
      "timeGroup": 2
    },
    {
      "pattern": "don'?t\\\\s+(?:let\\\\s+me\\\\s+)?forget\\\\s+(?:to\\\\s+)?(.+?)(?:\\\\s+(?:at|by|on|tomorrow|today|in)\\\\s+(.+?))?\\\\s*\$",
      "taskGroup": 1,
      "timeGroup": 2
    },
    {
      "pattern": "(?:i|we)\\\\s+need\\\\s+to\\\\s+(.+?)(?:\\\\s+(?:at|by|on|tomorrow|today|in)\\\\s+(.+?))?\\\\s*\$",
      "taskGroup": 1,
      "timeGroup": 2
    },
    {
      "pattern": "(?:i|we)\\\\s+(?:have\\\\s+to|must|should)\\\\s+(.+?)(?:\\\\s+(?:at|by|on|tomorrow|today|in)\\\\s+(.+?))?\\\\s*\$",
      "taskGroup": 1,
      "timeGroup": 2
    }
  ],
  "hi": [
    {
      "pattern": "मुझे\\\\s+(.+?)\\\\s+(?:याद|remind)\\\\s+(?:दिलाना|करना|कराना)(?:\\\\s+(.+?))?\\\\s*\$",
      "taskGroup": 1,
      "timeGroup": 2
    }
  ]
}
''';

void main() {
  late RuleEngine engine;

  setUp(() {
    engine = RuleEngine();
    final result = engine.loadFromJson(_testPatternsJson);
    expect(result.isOk, isTrue, reason: 'Patterns JSON should parse cleanly');
  });

  group('English patterns', () {
    test('remind me to call John at 3pm — extracts task and time', () {
      final match = engine.match('remind me to call John at 3pm', 'en');
      expect(match, isNotNull);
      expect(match!.task, contains('call John'));
      expect(match.timeStr, contains('3pm'));
    });

    test('reminder to buy milk — no time', () {
      final match = engine.match('reminder to buy milk', 'en');
      expect(match, isNotNull);
      expect(match!.task, contains('buy milk'));
      expect(match.timeStr, isNull);
    });

    test("don't forget to pick up the kids — extracts task", () {
      final match = engine.match("don't forget to pick up the kids", 'en');
      expect(match, isNotNull);
      expect(match!.task, contains('pick up the kids'));
    });

    test('I need to submit the report by 5pm', () {
      final match = engine.match('I need to submit the report by 5pm', 'en');
      expect(match, isNotNull);
      expect(match!.task, contains('submit the report'));
      expect(match.timeStr, contains('5pm'));
    });

    test('we have to leave by 9', () {
      final match = engine.match('we have to leave by 9', 'en');
      expect(match, isNotNull);
      expect(match!.task, contains('leave'));
    });

    test('no match for casual speech', () {
      expect(engine.match('the weather is nice today', 'en'), isNull);
      expect(engine.match('hello world', 'en'), isNull);
    });
  });

  group('Hindi patterns', () {
    test('मुझे दवाई लेना याद दिलाना — extracts task', () {
      final match = engine.match('मुझे दवाई लेना याद दिलाना', 'hi');
      expect(match, isNotNull);
      expect(match!.task, contains('दवाई लेना'));
    });
  });

  group('Language fallback', () {
    test('unknown language falls back to English patterns', () {
      final match = engine.match('remind me to call John', 'zh');
      expect(match, isNotNull);
    });

    test('English patterns used when language has no entry', () {
      final match = engine.match('I need to call the dentist', 'de');
      expect(match, isNotNull);
    });
  });

  group('Edge cases', () {
    test('empty string returns null', () {
      expect(engine.match('', 'en'), isNull);
    });

    test('match before load returns null', () {
      final freshEngine = RuleEngine();
      expect(freshEngine.match('remind me to do something', 'en'), isNull);
    });
  });
}
