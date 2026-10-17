import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:googleapis/calendar/v3.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import 'google_oauth.dart';

/// Handles adding calendar events:
/// 1. Primary: Google Calendar REST API via Google Sign-In (instant ~300ms, real-time cloud push & guaranteed alerts).
/// 2. Secondary: Automatic background insert into native Android Calendar.
/// 3. Tertiary: Native Google Calendar Intent with prefilled reminders.
/// 4. Fallback: Opens Google Calendar web render URL.
class CalendarLauncher {
  static const _channel = MethodChannel('com.openpendant.calendar');

  /// Attempts to insert the event silently via Google Calendar API or native Android.
  static Future<({bool automatic, bool success})> addOrOpenEvent({
    required String title,
    String description = '',
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    final start = startTime ?? DateTime.now();
    final end = endTime ?? start.add(const Duration(minutes: 30));

    // 1. Primary: Direct Google Calendar API (instant, guaranteed alerts on all devices)
    try {
      final client = await GoogleOAuthStore.getCalendarClient();
      if (client != null) {
        final api = CalendarApi(client);
        final desc = description.trim().isEmpty ? 'Krypton' : '$description\n\nKrypton';
        final event = Event(
          summary: title,
          description: desc,
          start: EventDateTime(dateTime: start.toUtc(), timeZone: 'UTC'),
          end: EventDateTime(dateTime: end.toUtc(), timeZone: 'UTC'),
          reminders: EventReminders(
            useDefault: false,
            overrides: [
              EventReminder(method: 'popup', minutes: 10),
              EventReminder(method: 'popup', minutes: 0),
            ],
          ),
        );
        final created = await api.events.insert(event, 'primary');
        client.close();
        if (created.id != null) {
          debugPrint('Google Calendar API: Event created with ID ${created.id}');
          return (automatic: true, success: true);
        }
      }
    } catch (e) {
      debugPrint('Google Calendar API insert failed: $e, falling back to local');
    }

    // 2. Secondary: Native Android background insert
    if (Platform.isAndroid) {
      try {
        var status = await Permission.calendarFullAccess.status;
        if (!status.isGranted) {
          status = await Permission.calendarFullAccess.request();
        }

        if (status.isGranted) {
          final bool? inserted = await _channel.invokeMethod<bool>(
            'insertCalendarEvent',
            {
              'title': title,
              'description': description,
              'startTime': start.millisecondsSinceEpoch,
              'endTime': end.millisecondsSinceEpoch,
            },
          );

          if (inserted == true) {
            return (automatic: true, success: true);
          }
        }
      } catch (_) {
        // Fall back
      }

      // 3. Fallback: Open native Google Calendar intent with prefilled reminders
      try {
        final bool? opened = await _channel.invokeMethod<bool>(
          'openCalendarIntent',
          {
            'title': title,
            'description': description,
            'startTime': start.millisecondsSinceEpoch,
            'endTime': end.millisecondsSinceEpoch,
          },
        );
        if (opened == true) {
          return (automatic: false, success: true);
        }
      } catch (_) {}
    }

    // 4. Fallback: Web template URL
    final launched = await openEvent(
      title: title,
      description: description,
      startTime: start,
      endTime: end,
    );

    return (automatic: false, success: launched);
  }

  static Future<bool> openEvent({
    required String title,
    String description = '',
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    final start = startTime ?? DateTime.now();
    final end = endTime ?? start.add(const Duration(minutes: 30));

    String formatUtc(DateTime dt) {
      final u = dt.toUtc();
      return '${u.year.toString().padLeft(4, '0')}'
          '${u.month.toString().padLeft(2, '0')}'
          '${u.day.toString().padLeft(2, '0')}T'
          '${u.hour.toString().padLeft(2, '0')}'
          '${u.minute.toString().padLeft(2, '0')}'
          '${u.second.toString().padLeft(2, '0')}Z';
    }

    final datesParam = '${formatUtc(start)}/${formatUtc(end)}';
    final desc = description.trim().isEmpty
        ? 'Created via Krypton'
        : '$description\n\nCreated via Krypton';

    final uri = Uri.parse(
      'https://calendar.google.com/calendar/render?action=TEMPLATE'
      '&text=${Uri.encodeComponent(title)}'
      '&dates=$datesParam'
      '&details=${Uri.encodeComponent(desc)}',
    );

    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
