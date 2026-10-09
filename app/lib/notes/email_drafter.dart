import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../stt/llm_key_store.dart';
import '../stt/openai_refine.dart';

class EmailDraft {
  EmailDraft({
    required this.subject,
    required this.body,
    this.suggestedTo = '',
  });

  final String subject;
  final String body;
  final String suggestedTo;
}

class EmailDrafter {
  EmailDrafter({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Drafts an action item follow-up email using the LLM (Groq / OpenAI).
  Future<EmailDraft> draftActionItem({
    required String task,
    String? meetingTitle,
    String? owner,
    String? deadline,
  }) async {
    final key = await LlmKeyStore.readKey();
    if (key.isEmpty) {
      return _fallbackActionDraft(task: task, owner: owner, deadline: deadline);
    }

    final url = OpenAiRefine.endpointFor(key);
    final model = OpenAiRefine.modelFor(key);

    final contextLines = <String>[
      'Task: $task',
      if (meetingTitle != null && meetingTitle.isNotEmpty) 'Meeting: $meetingTitle',
      if (owner != null && owner.isNotEmpty) 'Owner/Assignee: $owner',
      if (deadline != null && deadline.isNotEmpty) 'Deadline: $deadline',
    ];

    try {
      final res = await _client.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': model,
          'temperature': 0.3,
          'response_format': {'type': 'json_object'},
          'messages': [
            {
              'role': 'system',
              'content': 'You write concise, polite follow-up emails for action items from a meeting. '
                  'Max 120 words. Return a valid JSON object with keys "subject", "body", and "suggested_to".',
            },
            {
              'role': 'user',
              'content': 'Context:\n${contextLines.join('\n')}\n\n'
                  'Write a polite follow-up email. Return JSON: {"subject": "...", "body": "...", "suggested_to": "..."}',
            },
          ],
        }),
      ).timeout(const Duration(seconds: 25));

      if (res.statusCode >= 400) {
        return _fallbackActionDraft(task: task, owner: owner, deadline: deadline);
      }

      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final choices = json['choices'] as List<dynamic>? ?? [];
      if (choices.isEmpty) {
        return _fallbackActionDraft(task: task, owner: owner, deadline: deadline);
      }

      final content = (choices.first as Map<String, dynamic>)['message']?['content'] as String? ?? '{}';
      final parsed = jsonDecode(content) as Map<String, dynamic>;

      return EmailDraft(
        subject: (parsed['subject'] as String? ?? 'Follow-up: $task').trim(),
        body: (parsed['body'] as String? ?? '').trim(),
        suggestedTo: (parsed['suggested_to'] as String? ?? (owner ?? '')).trim(),
      );
    } catch (_) {
      return _fallbackActionDraft(task: task, owner: owner, deadline: deadline);
    }
  }

  /// Drafts a full meeting summary follow-up email.
  Future<EmailDraft> draftMeetingRecap({
    required String meetingTitle,
    required String recapHeadline,
    List<String> decisions = const [],
    List<String> actionItems = const [],
  }) async {
    final key = await LlmKeyStore.readKey();
    if (key.isEmpty) {
      return _fallbackRecapDraft(
        meetingTitle: meetingTitle,
        recapHeadline: recapHeadline,
        decisions: decisions,
        actionItems: actionItems,
      );
    }

    final url = OpenAiRefine.endpointFor(key);
    final model = OpenAiRefine.modelFor(key);

    final promptBuf = StringBuffer()
      ..writeln('Meeting: $meetingTitle')
      ..writeln('Headline: $recapHeadline');

    if (decisions.isNotEmpty) {
      promptBuf.writeln('Decisions:\n${decisions.map((d) => '- $d').join('\n')}');
    }
    if (actionItems.isNotEmpty) {
      promptBuf.writeln('Action items:\n${actionItems.map((a) => '- $a').join('\n')}');
    }

    try {
      final res = await _client.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': model,
          'temperature': 0.3,
          'response_format': {'type': 'json_object'},
          'messages': [
            {
              'role': 'system',
              'content': 'You write structured, polite recap emails after a meeting for team attendees. '
                  'Max 180 words. Return a valid JSON object with keys "subject", "body", and "suggested_to".',
            },
            {
              'role': 'user',
              'content': 'Details:\n${promptBuf.toString()}\n\n'
                  'Write a clear recap email. Return JSON: {"subject": "...", "body": "...", "suggested_to": ""}',
            },
          ],
        }),
      ).timeout(const Duration(seconds: 30));

      if (res.statusCode >= 400) {
        return _fallbackRecapDraft(
          meetingTitle: meetingTitle,
          recapHeadline: recapHeadline,
          decisions: decisions,
          actionItems: actionItems,
        );
      }

      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final choices = json['choices'] as List<dynamic>? ?? [];
      if (choices.isEmpty) {
        return _fallbackRecapDraft(
          meetingTitle: meetingTitle,
          recapHeadline: recapHeadline,
          decisions: decisions,
          actionItems: actionItems,
        );
      }

      final content = (choices.first as Map<String, dynamic>)['message']?['content'] as String? ?? '{}';
      final parsed = jsonDecode(content) as Map<String, dynamic>;

      return EmailDraft(
        subject: (parsed['subject'] as String? ?? 'Meeting Recap: $meetingTitle').trim(),
        body: (parsed['body'] as String? ?? '').trim(),
        suggestedTo: (parsed['suggested_to'] as String? ?? '').trim(),
      );
    } catch (_) {
      return _fallbackRecapDraft(
        meetingTitle: meetingTitle,
        recapHeadline: recapHeadline,
        decisions: decisions,
        actionItems: actionItems,
      );
    }
  }

  /// Opens the default email client (Gmail on Android) with prefilled fields.
  static Future<bool> openEmailClient({
    String to = '',
    required String subject,
    required String body,
  }) async {
    final uri = Uri(
      scheme: 'mailto',
      path: to.trim(),
      queryParameters: {
        'subject': subject.trim(),
        'body': body.trim(),
      },
    );

    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  EmailDraft _fallbackActionDraft({
    required String task,
    String? owner,
    String? deadline,
  }) {
    final greeting = (owner != null && owner.isNotEmpty) ? 'Hi $owner,' : 'Hi,';
    final due = (deadline != null && deadline.isNotEmpty) ? ' (Due: $deadline)' : '';
    final body = '$greeting\n\n'
        'Following up on the action item from our discussion:\n'
        '• $task$due\n\n'
        'Please let me know if you have any questions or need support.\n\n'
        'Best regards,';
    return EmailDraft(
      subject: 'Follow-up: $task',
      body: body,
      suggestedTo: owner ?? '',
    );
  }

  EmailDraft _fallbackRecapDraft({
    required String meetingTitle,
    required String recapHeadline,
    required List<String> decisions,
    required List<String> actionItems,
  }) {
    final buf = StringBuffer()
      ..writeln('Hi Team,\n')
      ..writeln('Here is a quick summary from our meeting "$meetingTitle":\n')
      ..writeln('Summary: $recapHeadline\n');

    if (decisions.isNotEmpty) {
      buf.writeln('Key Decisions:');
      for (final d in decisions) {
        buf.writeln('• $d');
      }
      buf.writeln();
    }

    if (actionItems.isNotEmpty) {
      buf.writeln('Next Steps & Action Items:');
      for (final a in actionItems) {
        buf.writeln('• $a');
      }
      buf.writeln();
    }

    buf.writeln('Best regards,');
    return EmailDraft(
      subject: 'Recap: $meetingTitle',
      body: buf.toString(),
    );
  }
}
