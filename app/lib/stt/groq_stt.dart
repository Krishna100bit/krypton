import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../audio/speech_vad.dart';
import '../db/models.dart';

class GroqStt {
  GroqStt({http.Client? client}) : _client = client ?? http.Client();

  static const modelId = 'whisper-large-v3-turbo';
  static const _url = 'https://api.groq.com/openai/v1/audio/transcriptions';

  final http.Client _client;

  Future<TranscriptResult> transcribe({
    required File wav,
    required String apiKey,
    required DateTime startedAt,
    SpeechExtract? speech,
  }) async {
    final key = apiKey.trim();
    if (key.isEmpty) {
      throw Exception('Groq API key is missing. Add it in Settings.');
    }

    final req = http.MultipartRequest('POST', Uri.parse(_url));
    req.persistentConnection = false;
    req.headers['Authorization'] = 'Bearer $key';
    req.headers['User-Agent'] = 'Mozilla/5.0 (compatible; Krypton/1.0)';
    req.fields['model'] = modelId;
    req.fields['response_format'] = 'verbose_json';
    req.fields['temperature'] = '0';
    req.fields['language'] = 'en';

    req.files.add(
      await http.MultipartFile.fromPath(
        'file',
        wav.path,
        filename: 'clip.wav',
      ),
    );

    final streamed =
        await _client.send(req).timeout(const Duration(seconds: 45));
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode >= 400) {
      String detail = body;
      try {
        final j = jsonDecode(body) as Map<String, dynamic>;
        detail = j['error']?['message']?.toString() ??
            j['detail']?.toString() ??
            body;
      } catch (_) {}
      throw Exception('Groq REST ${streamed.statusCode}: $detail');
    }

    final json = jsonDecode(body) as Map<String, dynamic>;
    final text = (json['text'] as String? ?? '').trim();
    final rawSegs = json['segments'] as List<dynamic>? ?? [];
    final segs = <TranscriptSegment>[];

    for (final item in rawSegs) {
      if (item is! Map) continue;
      final m = Map<String, dynamic>.from(item);
      final start = (m['start'] as num?)?.toDouble() ?? 0;
      final end = (m['end'] as num?)?.toDouble() ?? start;
      final origStart = speech?.originalSeconds(start) ?? start;
      final origEnd = speech?.originalSeconds(end) ?? end;
      final segText = (m['text'] as String? ?? '').trim();
      if (segText.isEmpty) continue;

      segs.add(
        TranscriptSegment(
          startS: origStart,
          endS: origEnd,
          spokenAt:
              startedAt.add(Duration(milliseconds: (origStart * 1000).round())),
          text: segText,
          rawText: segText,
          speaker: null,
        ),
      );
    }

    if (segs.isEmpty && text.isNotEmpty) {
      final origDuration = speech?.speechDurationS ?? 0.0;
      segs.add(
        TranscriptSegment(
          startS: 0,
          endS: origDuration,
          spokenAt: startedAt,
          text: text,
          rawText: text,
          speaker: null,
        ),
      );
    }

    return TranscriptResult(
      text: text,
      model: 'groq:$modelId',
      segments: segs,
      costUsd: 0, // Groq has generous free tier for whisper-large-v3-turbo
    );
  }
}

String friendlyGroqError(Object error) {
  final text = error.toString();
  final lower = text.toLowerCase();
  if (lower.contains('401') || lower.contains('invalid_api_key') || lower.contains('unauthorized')) {
    return 'Groq API key invalid. Check it in Settings.';
  }
  if (lower.contains('429') || lower.contains('rate_limit') || lower.contains('quota')) {
    return 'Groq rate limit reached. Please wait a moment.';
  }
  if (lower.contains('timeout')) {
    return 'Groq request timed out. Please retry.';
  }
  if (lower.contains('socketexception') ||
      lower.contains('failed host lookup') ||
      lower.contains('network is unreachable')) {
    return 'No internet connection to reach Groq.';
  }
  final clean = text.replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
  if (clean.length > 70) {
    return '${clean.substring(0, 67)}…';
  }
  return clean.isNotEmpty ? clean : 'Groq transcription failed. Please retry.';
}
