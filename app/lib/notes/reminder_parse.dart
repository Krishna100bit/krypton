/// What the user asked to be reminded of, and when (local clock).
class ParsedNoteReminder {
  const ParsedNoteReminder({required this.title, this.dueAt});

  final String title;
  final DateTime? dueAt;
}

const reminderLead = Duration(minutes: 15);
const reminderLeadShort = Duration(minutes: 5);

final _clock = RegExp(
  r"(?:\b(?:at|by|around|@)\s*)?"
  r"(?:"
  r"(?<clock>noon|midnight)|"
  r"(?<hour>\d{1,2})(?:\s*[:.]\s*(?<min>\d{2}))?"
  r"(?:\s*(?<mer>a\.?\s*m\.?|p\.?\s*m\.?))?"
  r"(?:\s*o['’]?\s*clock)?"
  r")"
  r"\b",
  caseSensitive: false,
);

final _months = <String, int>{
  'january': 1, 'jan': 1,
  'february': 2, 'feb': 2,
  'march': 3, 'mar': 3,
  'april': 4, 'apr': 4,
  'may': 5,
  'june': 6, 'jun': 6,
  'july': 7, 'jul': 7,
  'august': 8, 'aug': 8,
  'september': 9, 'sep': 9, 'sept': 9,
  'october': 10, 'oct': 10,
  'november': 11, 'nov': 11,
  'december': 12, 'dec': 12,
};

final _weekdays = <String, int>{
  'monday': DateTime.monday, 'mon': DateTime.monday,
  'tuesday': DateTime.tuesday, 'tue': DateTime.tuesday,
  'wednesday': DateTime.wednesday, 'wed': DateTime.wednesday,
  'thursday': DateTime.thursday, 'thu': DateTime.thursday,
  'friday': DateTime.friday, 'fri': DateTime.friday,
  'saturday': DateTime.saturday, 'sat': DateTime.saturday,
  'sunday': DateTime.sunday, 'sun': DateTime.sunday,
};

final _remindPrefix = RegExp(
  r'^(?:(?:hey|hi|okay|ok|please)\s+)*'
  r'(?:(?:set\s+(?:a\s+)?reminder|remind\s+me|reminder|schedule\s+(?:a\s+)?(?:task|meeting|event|reminder))\s+(?:to\s+|that\s+i\s+(?:need\s+to\s+|have\s+to\s+|should\s+)?|for\s+|on\s+|at\s+)?)?',
  caseSensitive: false,
);

final _explicitRemindWord = RegExp(
  r'\b(?:set\s+(?:a\s+)?reminder|remind(?:\s+me)?|reminder|schedule)\b',
  caseSensitive: false,
);

String reminderLabel(String text) {
  final parsed = parseNoteReminder(text);
  final title = parsed.title.trim();
  return title.isEmpty ? text.trim() : title;
}

class _DateMatch {
  _DateMatch({
    required this.targetDate,
    required this.start,
    required this.end,
    this.dayWord,
    this.hasDefaultHour = false,
    this.defaultHour = 9,
    this.relativeExactTime,
  });

  final DateTime targetDate;
  final int start;
  final int end;
  final String? dayWord;
  final bool hasDefaultHour;
  final int defaultHour;
  final DateTime? relativeExactTime;
}

/// Pull a local due time out of a spoken note or action item.
ParsedNoteReminder parseNoteReminder(
  String text, {
  DateTime? now,
  bool defaultTimeForDate = false,
}) {
  final clockNow = now ?? DateTime.now();
  var raw = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (raw.isEmpty) {
    return const ParsedNoteReminder(title: '');
  }

  final isExplicitReminder = _explicitRemindWord.hasMatch(raw) || defaultTimeForDate;
  final dateMatch = _findDateMatch(raw, clockNow, isExplicitReminder: isExplicitReminder);
  final clockMatch = _bestClock(raw);

  final due = _dueAt(
    now: clockNow,
    dateMatch: dateMatch,
    clock: clockMatch,
  );

  var title = raw;
  final spans = <List<int>>[
    if (clockMatch != null) [clockMatch.start, clockMatch.end],
    if (dateMatch != null) [dateMatch.start, dateMatch.end],
  ]..sort((a, b) => b[0].compareTo(a[0]));

  for (final s in spans) {
    if (s[0] < title.length && s[1] <= title.length && s[0] <= s[1]) {
      title = title.replaceRange(s[0], s[1], ' ');
    }
  }

  title = title.replaceAll(_remindPrefix, '');
  title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
  title = title.replaceAll(RegExp(r'^[\s,.:;\-]+|[\s,.:;\-]+$'), '');
  if (title.isEmpty) {
    title = raw;
  }
  if (title.isNotEmpty) {
    title = '${title[0].toUpperCase()}${title.substring(1)}';
  }
  return ParsedNoteReminder(title: title, dueAt: due);
}

_DateMatch? _findDateMatch(
  String raw,
  DateTime now, {
  required bool isExplicitReminder,
}) {
  // 1. Relative "in X minutes/hours/days/weeks"
  final rel = RegExp(
    r'\b(?:in\s+)?(\d{1,3})\s+(minute|minutes|min|mins|hour|hours|hr|hrs|day|days|week|weeks)\b',
    caseSensitive: false,
  ).firstMatch(raw);
  if (rel != null) {
    final count = int.tryParse(rel.group(1) ?? '') ?? 0;
    final unit = (rel.group(2) ?? '').toLowerCase();
    if (unit.startsWith('min')) {
      final t = now.add(Duration(minutes: count));
      return _DateMatch(
        targetDate: t,
        start: rel.start,
        end: rel.end,
        relativeExactTime: t,
      );
    } else if (unit.startsWith('h')) {
      final t = now.add(Duration(hours: count));
      return _DateMatch(
        targetDate: t,
        start: rel.start,
        end: rel.end,
        relativeExactTime: t,
      );
    } else if (unit.startsWith('d')) {
      final d = DateTime(now.year, now.month, now.day).add(Duration(days: count));
      return _DateMatch(
        targetDate: d,
        start: rel.start,
        end: rel.end,
        hasDefaultHour: true,
        defaultHour: 9,
      );
    } else if (unit.startsWith('w')) {
      final d = DateTime(now.year, now.month, now.day).add(Duration(days: count * 7));
      return _DateMatch(
        targetDate: d,
        start: rel.start,
        end: rel.end,
        hasDefaultHour: true,
        defaultHour: 9,
      );
    }
  }

  // 2. Day after tomorrow
  final dayAfter = RegExp(
    r'\b(?:the\s+)?day\s+after\s+tomorrow\b',
    caseSensitive: false,
  ).firstMatch(raw);
  if (dayAfter != null) {
    final d = DateTime(now.year, now.month, now.day).add(const Duration(days: 2));
    return _DateMatch(
      targetDate: d,
      start: dayAfter.start,
      end: dayAfter.end,
      dayWord: 'day after tomorrow',
      hasDefaultHour: true,
      defaultHour: 9,
    );
  }

  // 3. Tomorrow / Today / Tonight / Morning / Afternoon / Evening
  final basicDay = RegExp(
    r'\b(today|tonight|tomorrow|this\s+(?:morning|afternoon|evening))\b',
    caseSensitive: false,
  ).firstMatch(raw);
  if (basicDay != null) {
    final w = (basicDay.group(1) ?? '').toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    var d = DateTime(now.year, now.month, now.day);
    if (w == 'tomorrow') {
      d = d.add(const Duration(days: 1));
    }
    return _DateMatch(
      targetDate: d,
      start: basicDay.start,
      end: basicDay.end,
      dayWord: w,
      hasDefaultHour: (w == 'tomorrow' && isExplicitReminder) ||
          w == 'tonight' ||
          w == 'this evening' ||
          w == 'this morning' ||
          w == 'this afternoon',
      defaultHour: (w == 'tonight' || w == 'this evening')
          ? 20
          : (w == 'this afternoon' ? 15 : 9),
    );
  }

  // 4. "Next week"
  final nextWk = RegExp(r'\bnext\s+week\b', caseSensitive: false).firstMatch(raw);
  if (nextWk != null) {
    final d = DateTime(now.year, now.month, now.day).add(const Duration(days: 7));
    return _DateMatch(
      targetDate: d,
      start: nextWk.start,
      end: nextWk.end,
      hasDefaultHour: true,
      defaultHour: 9,
    );
  }

  // 5. Month names and dates (e.g. "15th October", "October 15", "15 Oct", "on 15th")
  const monthNames =
      'january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec';

  // Pattern: "15th October [2026]" or "15 of October"
  final dayThenMonth = RegExp(
    '\\b(?:on\\s+)?(?:the\\s+)?(\\d{1,2})(?:st|nd|rd|th)?(?:\\s+(?:of\\s+)?)?($monthNames)(?:\\s+(\\d{4}))?\\b',
    caseSensitive: false,
  ).firstMatch(raw);
  if (dayThenMonth != null) {
    final dayNum = int.tryParse(dayThenMonth.group(1) ?? '') ?? 1;
    final mStr = (dayThenMonth.group(2) ?? '').toLowerCase();
    final monthNum = _months[mStr] ?? now.month;
    final yr = int.tryParse(dayThenMonth.group(3) ?? '');
    final resolved = _resolveMonthDay(now, monthNum, dayNum, yr);
    return _DateMatch(
      targetDate: resolved,
      start: dayThenMonth.start,
      end: dayThenMonth.end,
      hasDefaultHour: true,
      defaultHour: 9,
    );
  }

  // Pattern: "October 15th [2026]"
  final monthThenDay = RegExp(
    '\\b(?:on\\s+)?($monthNames)\\s+(?:the\\s+)?(\\d{1,2})(?:st|nd|rd|th)?(?:\\s*,?\\s*(\\d{4}))?\\b',
    caseSensitive: false,
  ).firstMatch(raw);
  if (monthThenDay != null) {
    final mStr = (monthThenDay.group(1) ?? '').toLowerCase();
    final monthNum = _months[mStr] ?? now.month;
    final dayNum = int.tryParse(monthThenDay.group(2) ?? '') ?? 1;
    final yr = int.tryParse(monthThenDay.group(3) ?? '');
    final resolved = _resolveMonthDay(now, monthNum, dayNum, yr);
    return _DateMatch(
      targetDate: resolved,
      start: monthThenDay.start,
      end: monthThenDay.end,
      hasDefaultHour: true,
      defaultHour: 9,
    );
  }

  // Pattern: "on the 15th" / "on 24th" / "25th" / "for 25th" / "on 25"
  final ordinalDay = RegExp(
    r'\b(?:(?:on|for)\s+)?(?:the\s+|date\s+)?(\d{1,2})(?:st|nd|rd|th)\b|\b(?:on|for)\s+(?:the\s+|date\s+)?(\d{1,2})\b',
    caseSensitive: false,
  ).firstMatch(raw);
  if (ordinalDay != null) {
    final dayNum = int.tryParse(ordinalDay.group(1) ?? ordinalDay.group(2) ?? '') ?? 1;
    if (dayNum >= 1 && dayNum <= 31) {
      var resolved = DateTime(now.year, now.month, dayNum);
      if (resolved.isBefore(DateTime(now.year, now.month, now.day))) {
        resolved = DateTime(now.year, now.month + 1, dayNum);
      }
      return _DateMatch(
        targetDate: resolved,
        start: ordinalDay.start,
        end: ordinalDay.end,
        hasDefaultHour: true,
        defaultHour: 9,
      );
    }
  }

  // 6. Weekdays: "on Friday", "next Monday", "this Tuesday", "coming Wednesday"
  final weekdayMatch = RegExp(
    r'\b(?:(next|this|on|coming)\s+)?(monday|tuesday|wednesday|thursday|friday|saturday|sunday|mon|tue|wed|thu|fri|sat|sun)\b',
    caseSensitive: false,
  ).firstMatch(raw);
  if (weekdayMatch != null) {
    final mod = (weekdayMatch.group(1) ?? '').toLowerCase();
    final name = (weekdayMatch.group(2) ?? '').toLowerCase();
    final targetWk = _weekdays[name];
    if (targetWk != null) {
      final isNext = mod == 'next';
      var diff = (targetWk - now.weekday + 7) % 7;
      if (diff == 0) {
        if (isNext) {
          diff = 7;
        }
      } else if (isNext && diff < 7) {
        diff += 7;
      }
      final resolved = DateTime(now.year, now.month, now.day).add(Duration(days: diff));
      return _DateMatch(
        targetDate: resolved,
        start: weekdayMatch.start,
        end: weekdayMatch.end,
        hasDefaultHour: true,
        defaultHour: 9,
      );
    }
  }

  return null;
}

DateTime _resolveMonthDay(DateTime now, int month, int day, [int? year]) {
  var y = year ?? now.year;
  var candidate = DateTime(y, month, day);
  if (year == null) {
    final today = DateTime(now.year, now.month, now.day);
    if (candidate.isBefore(today)) {
      candidate = DateTime(now.year + 1, month, day);
    }
  }
  return candidate;
}

/// When the notification should fire. 15 minutes before the due time, or
/// 5 minutes if that would already have passed, or at due if even that is late.
DateTime? reminderFireAt({required DateTime due, required DateTime now}) {
  final floor = now.add(const Duration(seconds: 20));
  final long = due.subtract(reminderLead);
  if (long.isAfter(floor)) {
    return long;
  }
  final short = due.subtract(reminderLeadShort);
  if (short.isAfter(floor)) {
    return short;
  }
  if (due.isAfter(floor)) {
    return due;
  }
  return null;
}

DateTime nextDigestAt(DateTime now, {int hour = 8}) {
  var at = DateTime(now.year, now.month, now.day, hour);
  if (!at.isAfter(now)) {
    at = at.add(const Duration(days: 1));
  }
  return at;
}

RegExpMatch? _bestClock(String raw) {
  RegExpMatch? best;
  var bestScore = -1;
  for (final m in _clock.allMatches(raw)) {
    if (!_clockOk(m, raw)) {
      continue;
    }
    final mer = m.namedGroup('mer');
    final word = m.namedGroup('clock');
    var score = 1;
    if (word != null && word.isNotEmpty) {
      score = 3;
    } else if (mer != null && mer.isNotEmpty) {
      score = 2;
    }
    if (score > bestScore) {
      best = m;
      bestScore = score;
    }
  }
  return best;
}

bool _clockOk(RegExpMatch m, String raw) {
  final word = m.namedGroup('clock') ?? '';
  if (word.isNotEmpty) {
    return true;
  }
  final mer = m.namedGroup('mer') ?? '';
  if (mer.isNotEmpty) {
    return true;
  }
  final g = (m.group(0) ?? '').trim();
  if (RegExp(r"o['’]?\s*clock", caseSensitive: false).hasMatch(g)) {
    return true;
  }
  if (RegExp(r'^(?:at|by|around|@)\b', caseSensitive: false).hasMatch(g)) {
    return true;
  }
  final before = raw.substring(0, m.start).toLowerCase();
  return RegExp(r'(?:at|by|around|@)\s*$').hasMatch(before);
}

DateTime? _dueAt({
  required DateTime now,
  required _DateMatch? dateMatch,
  required RegExpMatch? clock,
}) {
  if (dateMatch?.relativeExactTime != null) {
    return dateMatch!.relativeExactTime;
  }

  var date = dateMatch?.targetDate ?? DateTime(now.year, now.month, now.day);
  final forced = dateMatch != null;

  int? hour;
  var minute = 0;
  if (clock != null) {
    final named = (clock.namedGroup('clock') ?? '').toLowerCase();
    if (named == 'noon') {
      hour = 12;
    } else if (named == 'midnight') {
      hour = 0;
      if (!forced) {
        if (now.hour == 0 && now.minute < 1) {
          date = DateTime(now.year, now.month, now.day);
        } else {
          date = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
        }
      }
    } else {
      hour = int.tryParse(clock.namedGroup('hour') ?? '');
      minute = int.tryParse(clock.namedGroup('min') ?? '') ?? 0;
    }
  }

  if (hour == null) {
    if (dateMatch != null && dateMatch.hasDefaultHour) {
      hour = dateMatch.defaultHour;
    } else {
      return null;
    }
  }

  if (hour > 24 || minute > 59) {
    return null;
  }

  final mer = (clock?.namedGroup('mer') ?? '')
      .toLowerCase()
      .replaceAll('.', '')
      .replaceAll(' ', '');
  if (mer.startsWith('p') && hour < 12) {
    hour += 12;
  } else if (mer.startsWith('a') && hour == 12) {
    hour = 0;
  } else if (mer.isEmpty &&
      hour >= 1 &&
      hour <= 12 &&
      clock?.namedGroup('clock') == null) {
    final am = DateTime(date.year, date.month, date.day, hour, minute);
    final pm = DateTime(
        date.year, date.month, date.day, hour == 12 ? 12 : hour + 12, minute);
    if (!forced) {
      if (am.isAfter(now.add(const Duration(seconds: 30)))) {
        hour = am.hour;
      } else if (pm.isAfter(now.add(const Duration(seconds: 30))) && hour != 12) {
        hour = pm.hour;
      } else {
        date = date.add(const Duration(days: 1));
      }
    } else if (hour <= 7 && dateMatch.dayWord == null) {
      // For general daytime meetings/reminders e.g. "at 4", prefer 4 PM over 4 AM
      hour = pm.hour;
    }
  }

  if (hour == 24) {
    hour = 0;
    date = date.add(const Duration(days: 1));
  }

  var due = DateTime(date.year, date.month, date.day, hour, minute);
  if (!forced && !due.isAfter(now.add(const Duration(seconds: 30)))) {
    due = due.add(const Duration(days: 1));
  }
  return due;
}
