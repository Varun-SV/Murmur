// Parses common English time expressions into DateTime values.
// Returns null for unrecognized strings — never throws.
class TimeParser {
  TimeParser._();

  static const _weekdays = {
    'monday': DateTime.monday,
    'tuesday': DateTime.tuesday,
    'wednesday': DateTime.wednesday,
    'thursday': DateTime.thursday,
    'friday': DateTime.friday,
    'saturday': DateTime.saturday,
    'sunday': DateTime.sunday,
  };

  static const _months = {
    'january': 1,
    'february': 2,
    'march': 3,
    'april': 4,
    'may': 5,
    'june': 6,
    'july': 7,
    'august': 8,
    'september': 9,
    'october': 10,
    'november': 11,
    'december': 12,
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
  };

  static DateTime? parse(String timeStr, {DateTime? now}) {
    final base = now ?? DateTime.now();
    final s = timeStr.trim().toLowerCase();

    // "in N minutes" / "in N hours"
    final inMinHour =
        RegExp(r'^in\s+(\d+)\s+(minute|minutes|hour|hours)$').firstMatch(s);
    if (inMinHour != null) {
      final n = int.parse(inMinHour.group(1)!);
      final unit = inMinHour.group(2)!;
      if (unit.startsWith('minute')) return base.add(Duration(minutes: n));
      return base.add(Duration(hours: n));
    }

    // "in N days" / "in a day" / "in N weeks" / "in a week"
    final inDayWeek = RegExp(
            r'^in\s+(a|\d+)\s+(day|days|week|weeks)$')
        .firstMatch(s);
    if (inDayWeek != null) {
      final raw = inDayWeek.group(1)!;
      final n = raw == 'a' ? 1 : int.parse(raw);
      final unit = inDayWeek.group(2)!;
      final days = unit.startsWith('week') ? n * 7 : n;
      final result = base.add(Duration(days: days));
      // Return at midnight of that day.
      return DateTime(result.year, result.month, result.day);
    }

    // "tomorrow morning/afternoon/evening"
    final tomorrowTod = RegExp(
            r'^tomorrow\s+(morning|afternoon|evening)$')
        .firstMatch(s);
    if (tomorrowTod != null) {
      final tomorrow = base.add(const Duration(days: 1));
      final hour = _timeOfDayHour(tomorrowTod.group(1)!);
      return DateTime(tomorrow.year, tomorrow.month, tomorrow.day, hour);
    }

    // "tomorrow at H[:MM][am|pm]"
    final tomorrowAt =
        RegExp(r'^tomorrow\s+at\s+(.+)$').firstMatch(s);
    if (tomorrowAt != null) {
      final t = _parseTime(tomorrowAt.group(1)!);
      if (t != null) {
        final tomorrow = base.add(const Duration(days: 1));
        return DateTime(
            tomorrow.year, tomorrow.month, tomorrow.day, t.$1, t.$2);
      }
    }

    // "today at H[:MM][am|pm]"
    final todayAt = RegExp(r'^today\s+at\s+(.+)$').firstMatch(s);
    if (todayAt != null) {
      final t = _parseTime(todayAt.group(1)!);
      if (t != null) {
        final candidate =
            DateTime(base.year, base.month, base.day, t.$1, t.$2);
        return _guardPast(candidate, base);
      }
    }

    // "this <weekday>"
    final thisDay = RegExp(
            r'^this\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)$')
        .firstMatch(s);
    if (thisDay != null) {
      final target = _weekdays[thisDay.group(1)!]!;
      // Find this weekday within the current week; if already past, use next.
      var d = DateTime(base.year, base.month, base.day);
      // Walk to the Monday of the current week, then to the target weekday.
      final daysFromMonday = (d.weekday - DateTime.monday) % 7;
      final monday = d.subtract(Duration(days: daysFromMonday));
      var candidate = monday
          .add(Duration(days: (target - DateTime.monday) % 7));
      if (!candidate.isAfter(d)) {
        candidate = candidate.add(const Duration(days: 7));
      }
      return candidate;
    }

    // "next <weekday>"
    final nextDay = RegExp(
            r'^next\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)$')
        .firstMatch(s);
    if (nextDay != null) {
      return _nextWeekday(base, _weekdays[nextDay.group(1)!]!,
          skipToday: true);
    }

    // "on <weekday> at H[:MM][am|pm]"
    final onDayAt = RegExp(
            r'^on\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\s+at\s+(.+)$')
        .firstMatch(s);
    if (onDayAt != null) {
      final t = _parseTime(onDayAt.group(2)!);
      if (t != null) {
        final day = _nextWeekday(base, _weekdays[onDayAt.group(1)!]!);
        return DateTime(day.year, day.month, day.day, t.$1, t.$2);
      }
    }

    // "May 15", "June 15th", "15th of June", "the 15th"
    final dated = _parseNamedDate(s, base);
    if (dated != null) return dated;

    // "at H[:MM][am|pm]" — advance to tomorrow if already past
    final atTime = RegExp(r'^at\s+(.+)$').firstMatch(s);
    if (atTime != null) {
      final t = _parseTime(atTime.group(1)!);
      if (t != null) {
        var candidate =
            DateTime(base.year, base.month, base.day, t.$1, t.$2);
        if (!candidate.isAfter(base)) {
          candidate = candidate.add(const Duration(days: 1));
        }
        return candidate;
      }
    }

    return null;
  }

  // Returns (hour24, minute) or null.
  // Fix: 12am = 00:00 (midnight), 12pm = 12:00 (noon).
  static (int, int)? _parseTime(String s) {
    // Matches: 3, 3pm, 3:45, 3:45pm, 3:45 pm
    final m =
        RegExp(r'^(\d{1,2})(?::(\d{2}))?\s*(am|pm)?$').firstMatch(s.trim());
    if (m == null) return null;

    var hour = int.parse(m.group(1)!);
    final minute = m.group(2) != null ? int.parse(m.group(2)!) : 0;
    final meridiem = m.group(3);

    if (meridiem == 'pm' && hour != 12) hour += 12; // 1pm–11pm → 13–23
    if (meridiem == 'am' && hour == 12) hour = 0;   // 12am → 0 (midnight)
    // 12pm stays 12 (noon) — no adjustment needed

    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return (hour, minute);
  }

  static int _timeOfDayHour(String tod) {
    switch (tod) {
      case 'morning':
        return 8;
      case 'afternoon':
        return 14;
      case 'evening':
        return 19;
      default:
        return 8;
    }
  }

  /// Returns the next occurrence of [weekday] from [from].
  /// If [skipToday] is true, always moves at least one day forward.
  static DateTime _nextWeekday(DateTime from, int weekday,
      {bool skipToday = false}) {
    var d = from.add(const Duration(days: 1));
    if (!skipToday) {
      // Allow same day if not yet past
      d = from;
    }
    while (d.weekday != weekday) {
      d = d.add(const Duration(days: 1));
    }
    return DateTime(d.year, d.month, d.day);
  }

  /// Parses named-date expressions and returns the nearest future date.
  /// Handles: "May 15", "June 15th", "15th of June", "the 15th"
  static DateTime? _parseNamedDate(String s, DateTime base) {
    // "May 15" / "June 15th"
    final monthDay = RegExp(
            r'^([a-z]+)\s+(\d{1,2})(?:st|nd|rd|th)?$')
        .firstMatch(s);
    if (monthDay != null) {
      final month = _months[monthDay.group(1)!];
      final day = int.tryParse(monthDay.group(2)!);
      if (month != null && day != null) {
        return _nearestFutureDate(base, month, day);
      }
    }

    // "15th of June" / "15 of June"
    final dayOfMonth = RegExp(
            r'^(\d{1,2})(?:st|nd|rd|th)?\s+of\s+([a-z]+)$')
        .firstMatch(s);
    if (dayOfMonth != null) {
      final day = int.tryParse(dayOfMonth.group(1)!);
      final month = _months[dayOfMonth.group(2)!];
      if (month != null && day != null) {
        return _nearestFutureDate(base, month, day);
      }
    }

    // "June 15th" already handled by monthDay above.
    // "the 15th" — ordinal only, use current month or next month.
    final theOrdinal =
        RegExp(r'^the\s+(\d{1,2})(?:st|nd|rd|th)?$').firstMatch(s);
    if (theOrdinal != null) {
      final day = int.tryParse(theOrdinal.group(1)!);
      if (day != null) {
        // Try current month first; if past, use next month.
        var candidate =
            DateTime(base.year, base.month, day);
        if (!candidate.isAfter(base)) {
          // Advance to next month
          final nextMonth = base.month == 12 ? 1 : base.month + 1;
          final nextYear = base.month == 12 ? base.year + 1 : base.year;
          candidate = DateTime(nextYear, nextMonth, day);
        }
        return candidate;
      }
    }

    return null;
  }

  /// Returns [month]/[day] in the nearest future year (this year if still
  /// in the future, otherwise next year).
  static DateTime _nearestFutureDate(DateTime base, int month, int day) {
    var candidate = DateTime(base.year, month, day);
    if (!candidate.isAfter(base)) {
      candidate = DateTime(base.year + 1, month, day);
    }
    return candidate;
  }

  /// If [result] is more than 60 seconds in the past relative to [base],
  /// adds 1 day.
  static DateTime _guardPast(DateTime result, DateTime base) {
    if (base.difference(result).inSeconds > 60) {
      return result.add(const Duration(days: 1));
    }
    return result;
  }
}
