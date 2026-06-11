import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

import 'package:murmur/core/result.dart';

final _log = Logger('RuleEngine');

// Hardcoded fallback patterns used when the JSON asset fails to load.
const _kFallbackPatterns = <Map<String, dynamic>>[
  {
    'pattern': r"remind me to (.+?) (?:at|by) (.+)",
    'taskGroup': 1,
    'timeGroup': 2,
  },
  {
    'pattern': r"don't forget to (.+)",
    'taskGroup': 1,
    'timeGroup': null,
  },
  {
    'pattern': r"remember to (.+?) (?:at|by) (.+)",
    'taskGroup': 1,
    'timeGroup': 2,
  },
  {
    'pattern': r"set a reminder (?:for|to) (.+)",
    'taskGroup': 1,
    'timeGroup': null,
  },
  {
    'pattern': r"add a reminder (?:for|to) (.+)",
    'taskGroup': 1,
    'timeGroup': null,
  },
  {
    'pattern': r"note to self[: ](.+)",
    'taskGroup': 1,
    'timeGroup': null,
  },
];

class RuleMatch {
  const RuleMatch({
    required this.task,
    this.timeStr,
    required this.matchedPattern,
  });

  final String task;
  final String? timeStr;
  final String matchedPattern;
}

class _PatternEntry {
  const _PatternEntry({
    required this.regex,
    required this.taskGroup,
    this.timeGroup,
  });

  final RegExp regex;
  final int taskGroup;
  final int? timeGroup;
}

class RuleEngine {
  final Map<String, List<_PatternEntry>> _patterns = {};
  bool _loaded = false;

  Future<Result<void>> load(AssetBundle bundle) async {
    try {
      final json = await bundle.loadString('assets/patterns/reminder_patterns.json');
      return loadFromJson(json);
    } catch (e, st) {
      _log.warning('Failed to load patterns asset — using built-in fallback patterns', e, st);
      return _loadFallback();
    }
  }

  Result<void> loadFromJson(String json) {
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      _patterns.clear();
      for (final entry in data.entries) {
        final lang = entry.key;
        final patternList = entry.value as List<dynamic>;
        final compiled = <_PatternEntry>[];
        for (final p in patternList) {
          final map = p as Map<String, dynamic>;
          final patternStr = map['pattern'] as String;
          RegExp re;
          try {
            re = RegExp(
              patternStr,
              caseSensitive: false,
              multiLine: false,
              unicode: true,
            );
          } on FormatException catch (fe) {
            _log.warning('Skipping invalid regex pattern "$patternStr": $fe');
            continue;
          }
          compiled.add(_PatternEntry(
            regex: re,
            taskGroup: map['taskGroup'] as int,
            timeGroup: map['timeGroup'] as int?,
          ));
        }
        _patterns[lang] = compiled;
      }
      _loaded = true;
      _log.info('Loaded patterns for languages: ${_patterns.keys.join(', ')}');
      return const Ok(null);
    } catch (e, st) {
      _log.severe('Failed to parse patterns JSON', e, st);
      return Err('Failed to parse reminder patterns: $e', cause: e as Object);
    }
  }

  Result<void> _loadFallback() {
    _patterns.clear();
    final compiled = <_PatternEntry>[];
    for (final map in _kFallbackPatterns) {
      final patternStr = map['pattern'] as String;
      RegExp re;
      try {
        re = RegExp(patternStr, caseSensitive: false);
      } on FormatException catch (fe) {
        _log.warning('Skipping invalid fallback regex "$patternStr": $fe');
        continue;
      }
      compiled.add(_PatternEntry(
        regex: re,
        taskGroup: map['taskGroup'] as int,
        timeGroup: map['timeGroup'] as int?,
      ));
    }
    _patterns['en'] = compiled;
    _loaded = true;
    _log.warning('Using built-in fallback English patterns (${compiled.length} patterns)');
    return const Ok(null);
  }

  RuleMatch? match(String text, String language) {
    if (!_loaded) {
      _log.warning('RuleEngine.match() called before load()');
      return null;
    }

    final candidates = [
      ...?_patterns[language],
      if (language != 'en') ...?_patterns['en'],
    ];

    for (final entry in candidates) {
      final m = entry.regex.firstMatch(text);
      if (m == null) continue;

      final task = m.group(entry.taskGroup)?.trim() ?? '';
      if (task.isEmpty) continue;

      String? timeStr;
      final tg = entry.timeGroup;
      if (tg != null && tg <= m.groupCount) {
        timeStr = m.group(tg)?.trim();
        if (timeStr != null && timeStr.isEmpty) timeStr = null;
      }

      return RuleMatch(
        task: task,
        timeStr: timeStr,
        matchedPattern: entry.regex.pattern,
      );
    }
    return null;
  }
}
