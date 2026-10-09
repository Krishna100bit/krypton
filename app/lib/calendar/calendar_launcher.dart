import 'package:url_launcher/url_launcher.dart';

/// Opens Google Calendar (app or web) prefilled with event details.
/// No complicated developer credentials needed; user simply taps Save.
class CalendarLauncher {
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
    final desc = description.trim().isEmpty ? 'Created via Krypton' : '$description\n\nCreated via Krypton';

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
