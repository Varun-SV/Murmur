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

  static DateTime? parse(String timeStr, {DateTime? now}) {
    final base = now ?? DateTime.now();
    final s = timeStr.trim().toLowerCase();

    // "in N minutes" / "in N hours"
    final inRel = RegExp(r'^in\s+(\d+)\s+(minute|minutes|hour|hours)$').firstMatch(s);
    if (inRel != null) {
      final n = int.parse(inRel.group(1)!);
      final unit = inRel.group(2)!;
      if (unit.startsWith('minute')) return base.add(Duration(minutes: n));
      return base.add(Duration(hours: n));
    }

    // "tomorrow at H[:MM][am|pm]"
    final tomorrowAt = RegExp(r'^tomorrow\s+at\s+(.+)$').firstMatch(s);
    if (tomorrowAt != null) {
      final t = _parseTime(tomorrowAt.group(1)!);
      if (t != null) {
        final tomorrow = base.add(const Duration(days: 1));
        return DateTime(tomorrow.year, tomorrow.month, tomorrow.day, t.$1, t.$2);
      }
    }

    // "today at H[:MM][am|pm]"
    final todayAt = RegExp(r'^today\s+at\s+(.+)$').firstMatch(s);
    if (todayAt != null) {
      final t = _parseTime(todayAt.group(1)!);
      if (t != null) {
        return DateTime(base.year, base.month, base.day, t.$1, t.$2);
      }
    }

    // "next <weekday>"
    final nextDay = RegExp(r'^next\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday)$')
        .firstMatch(s);
    if (nextDay != null) {
      return _nextWeekday(base, _weekdays[nextDay.group(1)!]!, skipToday: true);
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

    // "at H[:MM][am|pm]" — advance to tomorrow if already past
    final atTime = RegExp(r'^at\s+(.+)$').firstMatch(s);
    if (atTime != null) {
      final t = _parseTime(atTime.group(1)!);
      if (t != null) {
        var candidate = DateTime(base.year, base.month, base.day, t.$1, t.$2);
        if (!candidate.isAfter(base)) {
          candidate = candidate.add(const Duration(days: 1));
        }
        return candidate;
      }
    }

    return null;
  }

  // Returns (hour24, minute) or null.
  static (int, int)? _parseTime(String s) {
    // Matches: 3, 3pm, 3:45, 3:45pm, 3:45 pm
    final m = RegExp(r'^(\d{1,2})(?::(\d{2}))?\s*(am|pm)?$').firstMatch(s.trim());
    if (m == null) return null;

    var hour = int.parse(m.group(1)!);
    final minute = m.group(2) != null ? int.parse(m.group(2)!) : 0;
    final meridiem = m.group(3);

    if (meridiem == 'pm' && hour != 12) hour += 12;
    if (meridiem == 'am' && hour == 12) hour = 0;

    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return (hour, minute);
  }

  static DateTime _nextWeekday(DateTime from, int weekday, {bool skipToday = false}) {
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
}
