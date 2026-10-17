import 'package:googleapis/calendar/v3.dart';

import '../notes/reminder_parse.dart';
import 'google_oauth.dart';
import 'note_command.dart';

class CalendarNoteResult {
  CalendarNoteResult({required this.ok, this.detail = ''});

  final bool ok;
  final String detail;
}

Future<CalendarNoteResult> addNoteToGoogleCalendar(String note) async {
  final body = note.trim();
  if (body.isEmpty) {
    return CalendarNoteResult(ok: false, detail: 'Empty note');
  }
  final client = await GoogleOAuthStore.getCalendarClient();
  if (client == null) {
    return CalendarNoteResult(ok: false, detail: 'Not signed in to Google');
  }
  try {
    final now = DateTime.now();
    final parsed = parseNoteReminder(body, now: now, defaultTimeForDate: true);
    final start = (parsed.dueAt ?? now).toUtc();
    final end = start.add(const Duration(minutes: 30));
    final title = reminderLabel(body);

    final created = await CalendarApi(client).events.insert(
          Event(
            summary: calendarEventTitle(title.isNotEmpty ? title : body),
            description: '$body\n\nKrypton',
            start: EventDateTime(dateTime: start, timeZone: 'UTC'),
            end: EventDateTime(dateTime: end, timeZone: 'UTC'),
            reminders: EventReminders(
              useDefault: false,
              overrides: [
                EventReminder(method: 'popup', minutes: 10),
                EventReminder(method: 'popup', minutes: 0),
              ],
            ),
          ),
          'primary',
        );
    final link = created.htmlLink?.trim() ?? '';
    return CalendarNoteResult(
      ok: true,
      detail: link.isEmpty ? 'Added to Google Calendar with notifications' : link,
    );
  } finally {
    client.close();
  }
}
