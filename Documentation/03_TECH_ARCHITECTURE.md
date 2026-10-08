# 03 — Technical Architecture

## 1. Stack summary
| Layer | Choice | Notes |
|-------|--------|-------|
| Mobile app | Flutter (existing OpenPendant app) | Keep its state management (likely Provider); do not migrate |
| BLE | `flutter_blue_plus` (or whatever the repo already uses) | Keep existing connection code |
| Audio decode | Existing Opus decode path in the repo (e.g., `opus_dart`/`opus_flutter`) | Verify in P0 |
| Phone recording | `record` package (`startStream`, PCM16, 16 kHz, mono) | |
| WAV writing | Own small `WavWriter` (44-byte header + PCM) | |
| Local DB | `drift` (SQLite) + FTS5 | Local-first |
| HTTP | `dio` with retry interceptor | |
| Notifications | `flutter_local_notifications` + `timezone` | Exact alarms on Android |
| Calendar | `add_2_calendar` (native insert screen) | User confirms |
| Email handoff | `url_launcher` `mailto:` / Android share intent; optional Gmail API `drafts.create` | Human-final |
| Foreground service | `flutter_foreground_task` | Long recordings |
| Backend | Python 3.11, FastAPI, Pydantic v2, Uvicorn | |
| Jobs | FastAPI `BackgroundTasks` + SQLite job table | Redis only if time |
| ASR | `faster-whisper` (`small` default, `medium`/`large-v3` if GPU) | CTranslate2 |
| Diarization | `pyannote.audio` 3.1 (HF token) | Or WhisperX |
| Speaker embeddings | SpeechBrain `spkrec-ecapa-voxceleb` | Enrollment + matching |
| LLM (A) | Claude API | JSON-structured output with validation |
| LLM (B) | Ollama: `qwen2.5:7b-instruct` or `llama3.1:8b` | Local server |
| SLM (C) | Qwen2.5-1.5B-Instruct Q4_K_M (≈1 GB, Apache-2.0) or Gemma-class 1–2B | On phone; check license and size |
| On-device ASR (C) | whisper.cpp (`tiny.en`/`base.en`) or sherpa-onnx | Stretch |
| Embeddings | `bge-small-en-v1.5` or `all-MiniLM-L6-v2` | Server |
| Vector store | ChromaDB (persistent) | Server |
| Research | Tavily (or similar) search API | Thoughts only |
| Tests | pytest, `flutter test`, eval script | |

> Always verify package names, versions and licenses against pub.dev / PyPI / model cards on day 0. Packages in the on-device LLM space move fast.

## 2. Flutter app architecture (feature-first layers)
```
app/lib/
├─ core/            # env, theme, router, di, logger, permissions
├─ audio/
│  ├─ audio_source.dart            # abstract interface
│  ├─ phone_mic_source.dart
│  ├─ locket_ble_source.dart       # wraps existing BLE+Opus code
│  ├─ recording_session.dart       # owns source, WavWriter, timers
│  └─ wav_writer.dart
├─ data/
│  ├─ db/ (drift tables, DAOs, FTS5)
│  ├─ api/ (dio client, DTOs generated from contracts)
│  └─ repositories/ (meetings, actions, speakers, thoughts, drafts)
├─ ai/
│  ├─ inference_router.dart        # Tier A/B/C selection
│  ├─ remote_pipeline.dart
│  └─ local_slm.dart               # optional
├─ domain/
│  ├─ models/ (Meeting, Segment, Action, Decision, Draft…)
│  ├─ reminder_rules.dart          # pure Dart, fully unit tested
│  ├─ daily_summary.dart           # pure Dart template builder
│  └─ draft_state_machine.dart
├─ features/
│  ├─ home/  record/  meetings/  viewer/  minutes/
│  ├─ actions/  drafts/  ask/  thoughts/  speakers/  settings/
└─ main.dart
```
Rules: UI never calls BLE or HTTP directly; features call repositories/services. `domain/` has no Flutter imports (testable).

### AudioSource interface
```dart
abstract class AudioSource {
  String get id;                       // 'phone' | 'locket'
  Stream<Uint8List> get pcm16;         // 16 kHz mono little-endian PCM16
  Stream<SourceHealth> get health;     // connected, rssi, dropped packets, level
  Future<void> start();
  Future<void> stop();
}
```

## 3. Backend architecture
```
backend/app/
├─ main.py
├─ api/        meetings.py speakers.py ask.py actions.py thoughts.py summary.py health.py
├─ pipeline/   ingest.py asr.py diarize.py speaker_match.py zone.py extract.py chunk.py
├─ llm/        base.py claude_client.py ollama_client.py prompts/ schemas.py
├─ speakers/   enroll.py embeddings.py
├─ memory/     store.py retrieve.py answer.py
├─ jobs/       runner.py models.py
├─ core/       config.py db.py logging.py
└─ tests/
```
`llm/base.py` defines `LLMClient.generate_json(system, user, schema) -> dict` so Tier A and B are interchangeable.

## 4. Data schemas

### 4.1 App DB (SQLite via drift)
```sql
meetings(id TEXT PK, title TEXT, started_at INT, duration_s INT, source TEXT,        -- phone|locket|upload
         audio_path TEXT, status TEXT,                                               -- recorded|uploading|processing|ready|failed
         summary TEXT, minutes_json TEXT, server_id TEXT);
utterances(id TEXT PK, meeting_id TEXT, idx INT, speaker_id TEXT, start_s REAL, end_s REAL, text TEXT);
segments(id TEXT PK, meeting_id TEXT, idx INT, zone TEXT,                            -- discussion|decision|action
         start_idx INT, end_idx INT, start_s REAL, end_s REAL, summary TEXT, confidence REAL);
decisions(id TEXT PK, meeting_id TEXT, segment_id TEXT, text TEXT, decided_by TEXT, rationale TEXT);
actions(id TEXT PK, meeting_id TEXT, segment_id TEXT, task TEXT, owner_name TEXT, owner_speaker_id TEXT,
        owner_inferred INT, deadline_ts INT NULL, deadline_inferred INT, priority TEXT, status TEXT,   -- open|done|snoozed
        source_quote TEXT, created_at INT);
reminders(id TEXT PK, action_id TEXT, fire_at INT, kind TEXT, notif_id INT, state TEXT);              -- pending|fired|cancelled
email_drafts(id TEXT PK, action_id TEXT, to_json TEXT, subject TEXT, body TEXT, state TEXT,
             created_at INT, approved_at INT NULL, sent_at INT NULL);
speakers(id TEXT PK, name TEXT, enrolled_at INT);                                    -- embeddings live on server
thoughts(id TEXT PK, text TEXT, created_at INT, recap TEXT, research_md TEXT, sources_json TEXT, tags TEXT);
names_vault(id TEXT PK, name TEXT, note TEXT, created_at INT);
CREATE VIRTUAL TABLE chunks_fts USING fts5(meeting_id UNINDEXED, ref UNINDEXED, text);
```

### 4.2 Server DB (SQLite) additions
`jobs(id, meeting_id, stage, progress, error, timings_json)`, `speaker_embeddings(speaker_id, vector BLOB, samples INT)`, plus a Chroma collection `chunks` (metadata: meeting_id, start_s, end_s, zone, speakers).

## 5. API contract (OpenAPI source: `contracts/openapi.yaml`)
| Method | Path | Body | Returns |
|--------|------|------|---------|
| GET | `/v1/health` | – | status, models loaded, tier |
| POST | `/v1/meetings` | multipart audio **or** JSON transcript, `title`, `started_at`, `source` | `{meeting_id, job_id}` |
| GET | `/v1/jobs/{id}` | – | `{stage, progress, error?}` |
| GET | `/v1/meetings` | – | list |
| GET | `/v1/meetings/{id}` | – | full minutes JSON (schema in file 06) |
| POST | `/v1/speakers/enroll` | audio, name | `{speaker_id, quality}` |
| POST | `/v1/speakers/test` | audio (~5 s) | `{matches:[{name, score}], best, threshold}` |
| GET | `/v1/speakers` | – | list |
| POST | `/v1/ask` | `{question, meeting_id?, filters?}` | `{answer, citations:[{meeting_id, start_s, quote}]}` |
| POST | `/v1/actions/{id}/draft-email` | `{tone?}` | `{subject, body, suggested_to:[]}` (**generates text only; never sends**) |
| POST | `/v1/thoughts` | text or audio | `{id, recap}` |
| POST | `/v1/thoughts/{id}/research` | – | `{research_md, sources}` |
| POST | `/v1/brainstorm` | `{thought_id, messages[]}` | `{reply}` |
| POST | `/v1/recap` | `{meeting_id}` | `{recap}` (Tier A/B) |

Auth for hackathon: header `X-Krypton-Token` from env. Errors use `{error:{code,message}}`.

## 6. Configuration
`backend/.env`: `ANTHROPIC_API_KEY`, `LLM_PROVIDER=claude|ollama`, `OLLAMA_URL`, `WHISPER_MODEL=small`, `HF_TOKEN`, `TAVILY_API_KEY`, `KRYPTON_TOKEN`, `DATA_DIR`.
App: server URL, tier preference (Auto/A/B/C), recap model, reminder quiet hours, daily summary time.

## 7. Performance budget (targets)
| Stage | Budget (10 min audio, Tier A, decent CPU or GPU) |
|-------|-----------------------------------|
| Upload | < 5 s on Wi-Fi |
| ASR (`small`, GPU) | ~20–40 s; CPU may be 2–4 min, so use `base` for demos on CPU |
| Diarization | 30–60 s |
| LLM zoning + extraction | 15–40 s |
| Embedding + store | < 5 s |
Pre-process demo clips ahead of time; show a progress bar for live runs.

## 8. Model notes
- **Whisper:** `small.en` for English demos, multilingual `small` for Hinglish; word timestamps on.
- **SLM:** keep context ≤ 2k tokens by feeding structured minutes; Q4 quantization; one model download shown in Settings with a size warning.
- Do not claim on-device diarization unless it actually works; mark it experimental.
