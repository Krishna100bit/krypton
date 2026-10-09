import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

/// Handles adding calendar events:
/// 1. Primary: Automatic background insert into native Android Calendar (0 taps needed).
/// 2. Fallback: Opens Google Calendar app prefilled if permission is denied.
class CalendarLauncher {
  static const _channel = MethodChannel('com.openpendant.calendar');

  /// Attempts to insert the event silently in the background on Android.
  /// Falls back to launching the Calendar app if not supported or permission denied.
  static Future<({bool automatic, bool success})> addOrOpenEvent({
    required String title,
    String description = '',
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    final start = startTime ?? DateTime.now();
    final end = endTime ?? start.add(const Duration(minutes: 30));

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
        // Fall back to opening calendar
      }
    }

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
