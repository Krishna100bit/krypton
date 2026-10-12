import 'package:flutter_test/flutter_test.dart';
import 'package:openpendant/notes/reminder_parse.dart';

void main() {
  final morning = DateTime(2026, 9, 3, 8, 0);
  final midday = DateTime(2026, 9, 3, 11, 0);
  final evening = DateTime(2026, 9, 3, 19, 0);

  test('remind me at 10 AM is today when it is still morning', () {
    final p = parseNoteReminder(
      'Remind me to call mom at 10 AM',
      now: morning,
    );
    expect(p.title, 'Call mom');
    expect(p.dueAt, DateTime(2026, 9, 3, 10));
  });

  test('10 AM already passed rolls to tomorrow', () {
    final p = parseNoteReminder(
      'remind me to call mom at 10 AM',
      now: midday,
    );
    expect(p.dueAt, DateTime(2026, 9, 4, 10));
  });

  test('3:30 p.m. with minutes', () {
    final p = parseNoteReminder(
      'pick up laundry at 3:30 p.m.',
      now: morning,
    );
    expect(p.title.toLowerCase(), contains('laundry'));
    expect(p.dueAt, DateTime(2026, 9, 3, 15, 30));
  });

  test('bare at 10 picks the next 10 o clock', () {
    expect(
      parseNoteReminder('remind me to eat at 10', now: morning).dueAt,
      DateTime(2026, 9, 3, 10),
    );
    expect(
      parseNoteReminder('remind me to eat at 10', now: midday).dueAt,
      DateTime(2026, 9, 3, 22),
    );
  });

  test('tomorrow without a clock is a digest note', () {
    final p = parseNoteReminder('buy milk tomorrow', now: evening);
    expect(p.dueAt, isNull);
    expect(p.title.toLowerCase(), contains('milk'));
  });

  test('tomorrow at 9 is 9 AM the next day', () {
    final p = parseNoteReminder('remind me tomorrow at 9', now: evening);
    expect(p.dueAt, DateTime(2026, 9, 4, 9));
  });

  test('no clock means no due time', () {
    expect(parseNoteReminder('buy milk', now: morning).dueAt, isNull);
    expect(
      parseNoteReminder('remind me to submit the report', now: morning).dueAt,
      isNull,
    );
  });

  test('random numbers are not times', () {
    expect(
      parseNoteReminder('buy 2 litres of milk', now: morning).dueAt,
      isNull,
    );
  });

  test('Hindi transcript is stored as-is and is not a clock', () {
    const hi = 'मेरा नाम क्या है कल मिलते हैं';
    final p = parseNoteReminder(hi, now: morning);
    expect(p.dueAt, isNull);
    expect(p.title, hi);
  });

  test('noon and midnight', () {
    expect(
      parseNoteReminder('meet at noon', now: morning).dueAt,
      DateTime(2026, 9, 3, 12),
    );
    expect(
      parseNoteReminder('take medicine at midnight', now: evening).dueAt,
      DateTime(2026, 9, 4, 0),
    );
  });

  test('fire 15 minutes before, or 5 if that already passed', () {
    expect(
      reminderFireAt(
        due: DateTime(2026, 9, 3, 10),
        now: DateTime(2026, 9, 3, 8),
      ),
      DateTime(2026, 9, 3, 9, 45),
    );
    expect(
      reminderFireAt(
        due: DateTime(2026, 9, 3, 10),
        now: DateTime(2026, 9, 3, 9, 50),
      ),
      DateTime(2026, 9, 3, 9, 55),
    );
    expect(
      reminderFireAt(
        due: DateTime(2026, 9, 3, 10),
        now: DateTime(2026, 9, 3, 9, 58),
      ),
      DateTime(2026, 9, 3, 10),
    );
    expect(
      reminderFireAt(
        due: DateTime(2026, 9, 3, 10),
        now: DateTime(2026, 9, 3, 10, 1),
      ),
      isNull,
    );
  });

  test('next digest is 8 AM tomorrow after 8 AM', () {
    expect(
      nextDigestAt(DateTime(2026, 9, 3, 8, 10)),
      DateTime(2026, 9, 4, 8),
    );
    expect(
      nextDigestAt(DateTime(2026, 9, 3, 7, 50)),
      DateTime(2026, 9, 3, 8),
    );
  });

  test('set reminder on 15th October at 4 PM', () {
    final p = parseNoteReminder(
      'Set reminder on 15th October at 4 PM to submit proposal',
      now: morning,
    );
    expect(p.dueAt, DateTime(2026, 10, 15, 16));
    expect(p.title.toLowerCase(), contains('submit proposal'));
  });

  test('remind me on Friday at 5 PM', () {
    // 2026-09-03 was a Thursday (weekday 4). Friday is 2026-09-04 (weekday 5).
    final p = parseNoteReminder(
      'Remind me on Friday at 5 PM to call client',
      now: morning,
    );
    expect(p.dueAt, DateTime(2026, 9, 4, 17));
    expect(p.title.toLowerCase(), contains('call client'));
  });

  test('set reminder on October 15 without clock defaults to 9 AM', () {
    final p = parseNoteReminder(
      'Set reminder on October 15 to file taxes',
      now: morning,
    );
    expect(p.dueAt, DateTime(2026, 10, 15, 9));
    expect(p.title.toLowerCase(), contains('file taxes'));
  });

  test('explicit reminder tomorrow defaults to 9 AM next day', () {
    final p = parseNoteReminder(
      'Remind me tomorrow to renew insurance',
      now: morning,
    );
    expect(p.dueAt, DateTime(2026, 9, 4, 9));
    expect(p.title.toLowerCase(), contains('renew insurance'));
  });

  test('relative in 2 hours', () {
    final p = parseNoteReminder(
      'Check oven in 2 hours',
      now: morning,
    );
    expect(p.dueAt, morning.add(const Duration(hours: 2)));
    expect(p.title.toLowerCase(), contains('check oven'));
  });
}
