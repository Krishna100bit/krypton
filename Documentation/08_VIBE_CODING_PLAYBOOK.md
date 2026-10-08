# 08 — Vibe Coding Playbook

How to build this with AI coding tools (Claude Code, Cursor, Copilot, etc.) without the codebase turning into soup.

## 1. Working agreement
1. **Docs are the source of truth.** Paste the relevant doc section into each prompt; don't rely on the tool "remembering".
2. **Contracts first.** Schema and API change only by editing `contracts/` first, then regenerating models.
3. **One phase = one branch = one PR-sized change.** Merge only when the phase exit criteria pass.
4. **Small prompts, runnable output.** Every prompt ends with "and show me how to run/test it".
5. **Test the risky logic by hand-written tests**, not AI vibes: reminder rules, draft approval gate, zoning validator.
6. **Pin working states:** `git tag gate-G3` etc. Roll back instead of debugging for more than 20 minutes.
7. **Humans review:** security-sensitive code (send gate, permissions) must be read by a person.

## 2. `AGENTS.md` (put in repo root; also usable as `.cursorrules` / `CLAUDE.md`)
```markdown
# Krypton v2 — Rules for AI coding agents

## Project
Flutter app (app/) + FastAPI backend (backend/) for meeting minutes with zones (discussion/decision/action).
Read docs/ before large changes: 02 system arch, 03 tech arch, 06 AI spec, 07 reminders+email.

## Hard rules
- Never add code that sends an email or creates a calendar event without an explicit user confirmation UI step. Email send path requires DraftState.approved with a fresh approval token.
- Never put API keys in the app. Secrets only in backend/.env.
- Audio contract: 16 kHz, mono, PCM16, WAV. Do not change.
- Contracts live in contracts/. If you need a new field, edit the schema first and update both sides.
- Reminder times come only from domain/reminder_rules.dart (pure function). Do not let an LLM choose notification times.
- LLM output must be validated with Pydantic; never trust raw model text.
- Reference transcript evidence by utterance index, not by quoted text.
- Keep the existing OpenPendant BLE code working; wrap it, don't rewrite it.

## Style
- Dart: null-safe, small widgets, no business logic in widgets, domain/ has no Flutter imports.
- Python: type hints, Pydantic v2, async endpoints, no global state except config.
- Add or update tests for any change in domain/ (Dart) or pipeline/ (Python).
- Prefer simple and boring over clever. No new dependencies without a one-line reason in the PR description.

## Workflow
1. Restate the task and list files you will touch.
2. Make the smallest change that satisfies the exit criteria.
3. Run tests/analyzer: `flutter analyze && flutter test`, `pytest -q`.
4. Summarize what changed and how to verify manually.

## Don't
- Don't delete existing files unless asked. Don't reformat unrelated code. Don't upgrade Flutter/major packages. Don't add telemetry.
```

## 3. Standard prompt template
```
Context: Krypton v2 (see AGENTS.md). We are in Phase {N}: {name}.
Goal: {one sentence}
Relevant spec: {paste the section from the docs}
Files to create/modify: {list}
Constraints: {2–4 bullets, e.g., pure Dart, no new deps}
Acceptance: {exit criteria from file 04}
Please: 1) list your plan, 2) implement, 3) add tests, 4) tell me exact commands to run and what I should see.
```

## 4. Phase prompts (copy, adapt, run)

### P0 — Audit
```
Audit the Flutter app in app/ for how BLE audio from the locket becomes playable audio. Find: BLE service/characteristic UUIDs, codec handling (Opus), where audio is stored, any Firebase/auth/backend dependencies, state management approach. Output docs/audit.md with file paths and a 5-line explanation of the audio flow. Also list what must be stubbed to run without login. Do not change code.
```
```
Create contracts/minutes.schema.json from the schema in docs/06_AI_PIPELINE_SPEC.md §2, and three fixtures in contracts/fixtures/ (transcript.txt + expected.json) for: a product planning meeting, a standup, a client call. Make the fixtures realistic with clear decisions, actions, owners and relative deadlines.
```

### P1 — AI core (text → minutes)
```
In backend/, implement: llm/base.py (LLMClient.generate_json), llm/claude_client.py, llm/schemas.py (Pydantic models matching contracts/minutes.schema.json), pipeline/zone.py and pipeline/extract.py using the prompt in docs/06 §4, and pipeline/validate.py implementing §4 validation + repair (coverage, referential integrity, date sanity, heuristic fallback). Add eval/run_eval.py that runs all fixtures and prints coverage validity, action recall, owner accuracy. Add pytest tests for the validator with bad inputs (gaps, overlaps, missing segment ids).
```

### P2 — ASR + API
```
Add pipeline/asr.py using faster-whisper (model from env, word timestamps, VAD) and pipeline/ingest.py (ffmpeg normalize to 16k mono WAV). Implement FastAPI endpoints per docs/03 §5: /v1/health, POST /v1/meetings (multipart audio or JSON transcript), GET /v1/jobs/{id}, GET /v1/meetings, GET /v1/meetings/{id}. Use a job table in SQLite and BackgroundTasks with stages ingest→asr→zone→extract→done and progress. Provide curl examples and a sample audio test.
```

### P3 — Flutter capture
```
In app/, add lib/audio/{audio_source,phone_mic_source,recording_session,wav_writer}.dart per docs/05 §4–5. Use the `record` package streaming PCM16 16kHz mono. RecordingSession writes the WAV continuously, exposes elapsed/level/state, and finalizes headers on stop. Add a unit test with a fake AudioSource producing 3 seconds of sine wave and verify a valid WAV. Then add a Record screen with timer, level meter, consent banner, and stop → create a meetings row in drift.
```
```
Add drift tables (meetings, utterances, segments, decisions, actions, reminders, email_drafts, speakers, thoughts, chunks_fts) per docs/03 §4.1 and repositories. Add UploadQueue with dio retry/backoff that posts meetings to /v1/meetings, polls /v1/jobs/{id}, then stores the minutes JSON into the tables. Show status chips on the meetings list.
```

### P4 — Viewer + minutes
```
Build the Meeting detail screen with two tabs. Tab 1 Zone viewer per docs/05 §10: utterances grouped by segment with zone colour + icon + label, speaker chips, legend filter, search. Tab 2 Minutes: summary, Decisions list, Actions table (editable). Tapping a decision/action scrolls to and highlights the source utterance. Load from contracts/fixtures/*/expected.json when offline-dev flag is on.
```

### P5 — Locket source
```
Using the existing BLE/Opus code found in docs/audit.md, create lib/audio/locket_ble_source.dart implementing AudioSource without changing existing behaviour. Emit PCM16 16kHz mono. Add health stream (connected, rssi, dropped frames, last packet time), reconnect with backoff, and a UI source selector on Home (Phone | Locket | Auto) with a pairing sheet. If the locket disconnects, keep the WAV and show a banner with "Continue on phone".
```

### P6 — Reminders
```
Implement lib/domain/reminder_rules.dart exactly per docs/07 §1 (pure Dart, injected `now`) plus tests covering the 9 scenarios in §1.5. Then implement ReminderScheduler using flutter_local_notifications + timezone with actions Done/Snooze, re-sync on app start, and permission handling for Android 13+/exact alarms. Add a debug button "Schedule test reminder in 2 minutes".
```

### P7 — Email + calendar
```
Implement lib/domain/draft_state_machine.dart and the Review & Send flow per docs/07 §3. Enforce the 7 invariants with unit tests (sendHandoff throws unless APPROVED with a fresh single-use token minted by ConfirmSendDialog; edit resets approval). Backend: POST /v1/actions/{id}/draft-email returning subject/body only. Handoff via mailto/Android intent. Add "Add to calendar" using add_2_calendar.
```

### P8 — Speakers
```
Backend: speakers/embeddings.py (SpeechBrain ECAPA), endpoints /v1/speakers/enroll, /test, list; pipeline/diarize.py (pyannote 3.1) and pipeline/speaker_match.py per docs/06 §1 and §6 with calibratable threshold in config. App: Speakers screen with enroll (record 15 s, show quality) and Test sample (record 5 s, show best match + score), and rename "Speaker N" inside a meeting.
```

### P9 — Memory
```
Backend: memory/{store,retrieve,answer}.py with Chroma + bge-small, chunking per docs/06 §7, POST /v1/ask returning answer + citations (meeting_id, start_s). App: Ask screen with filters and tappable citations that open the meeting at that timestamp. Also fill the local FTS5 table after each meeting and use it when offline.
```

### P10 — Offline tiers
```
Backend: llm/ollama_client.py implementing LLMClient; LLM_PROVIDER switch; lower temperature and stricter JSON retry. App: InferenceRouter (Auto/A/B/C) with health checks and a visible tier badge. Then, optional: local_slm.dart that downloads a Q4 1.5B model on demand and generates a 4-line recap from structured minutes with a 60s timeout and an extractive fallback (docs/06 §8). Mark as Experimental in UI.
```

### P11 — Thoughts + daily summary
```
Add Thoughts: quick-capture button (voice or text), backend /v1/thoughts (recap+tags), /research (Tavily + sourced summary), /brainstorm chat. Detect trigger phrases in utterances per docs/06 §9. Add DailySummary template builder (pure Dart, per docs/07 §6) and a daily local notification at the configured time.
```

### P12 — Polish
```
Create a QA checklist run-through: fix crashes, empty states, loading states, and error messages for: no network, mic denied, BLE off, backend down, invalid JSON. Add a demo mode that seeds three prepared meetings and enrolled speakers. Prepare release APK build instructions.
```

## 5. Debugging prompts
```
Here is the error and the relevant file. Explain the root cause in two sentences, then give the smallest fix. Do not refactor.
```
```
This works on the emulator but fails on the physical phone. List the three most likely causes related to permissions, BLE, or audio format, and the log lines that would confirm each.
```
```
The LLM returned invalid JSON for this transcript (paste). Improve the prompt or validator minimally; show a failing test first.
```

## 6. Context hygiene
- Start a fresh chat per phase; paste AGENTS.md + the doc excerpt.
- Keep a `docs/STATE.md` updated at each gate: what works, what's broken, next 3 tasks. Paste it into new sessions.
- Don't let the tool "improve" architecture mid-hackathon.

## 7. Team workflow
- Branches: `feat/p3-capture`, `feat/p1-ai-core`… Merge to `main` only at green gates.
- Two people must not edit the same file; the schema and API are the only shared surfaces.
- Everyone pulls `main` every hour; demo build is always built from `main`.
- Daily-driver commands: `flutter analyze && flutter test`, `pytest -q`, `python eval/run_eval.py`.
