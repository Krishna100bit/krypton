# 04 — Roadmap (Phases, Tracks, Gates)

## 1. How to read this
24 hours, a team, mostly vibe-coded. Work is split into **phases (P0–P11)**, each small enough for one AI-assisted session (30–120 min), with a clear **exit criterion**. Four parallel **tracks**: **A** Flutter app, **B** Backend/AI, **C** Hardware + integration, **D** Pitch/QA.

Priority tags: **[CORE]** required by PS 04 · **[DIFF]** differentiator · **[STRETCH]** cut first.

## 2. Phase table
| Phase | Name | Track | Time box | Depends on | Tag |
|-------|------|-------|----------|-----------|-----|
| P0 | Foundations, repo audit, contracts | All | 0:00–1:30 | – | CORE |
| P1 | AI core on text (zoning + extraction) | B | 1:30–5:00 | P0 | CORE |
| P2 | ASR + job pipeline + API | B | 3:00–8:00 | P0 | CORE |
| P3 | Flutter capture abstraction + phone recording + upload | A | 1:30–7:00 | P0 | CORE |
| P4 | Zone viewer + minutes UI | A | 6:00–12:00 | P1, P3 | CORE |
| P5 | Locket as AudioSource | C | 6:00–11:00 | P3 | CORE (PS differentiator) |
| P6 | Reminders engine + notifications | A | 9:00–13:00 | P4 | DIFF |
| P7 | Email drafts + approval gate + calendar | A+B | 11:00–15:00 | P4 | DIFF |
| P8 | Speaker enrollment, test, identification | B+A | 10:00–16:00 | P2 | DIFF |
| P9 | Memory search + recap Q&A | B+A | 14:00–18:00 | P2, P4 | DIFF |
| P10 | Offline tiers: Ollama (B) then on-device SLM (C) | B+A | 16:00–20:00 | P9 | STRETCH |
| P11 | Thoughts + daily closing summary | A+B | 18:00–21:00 | P9 | STRETCH |
| P12 | Freeze, polish, demo, pitch, backup video | All | 21:00–24:00 | – | CORE |

## 3. Gates (stop and check)
| Gate | Time | Must be true | If not |
|------|------|--------------|--------|
| G0 | 1:30 | Contracts in repo, fixtures exist, app builds and runs, BLE audit written | Fix before anything else |
| G1 | 5:00 | Text transcript → valid minutes JSON for 3 fixtures | Simplify prompt; use few-shot; smaller schema |
| G2 | 8:00 | Audio file → minutes via API | Use `base` Whisper; skip diarization for now |
| G3 | 12:00 | **Phone recording → upload → zone viewer + minutes works on a real phone** | Drop all stretch work; fix this |
| G4 | 15:00 | Locket recording works OR fallback decided | Ship phone + upload; demo locket as pre-recorded clip |
| G5 | 18:00 | At least 2 of: speaker ID, reminders, drafts, memory working | Cut remaining DIFF items |
| G6 | 21:00 | **Feature freeze** | Only bug fixes after this |

## 4. Phase details
Each phase lists: Goal · Tasks · Deliverables · Exit criteria.

### P0 — Foundations (0:00–1:30)
- Fork/clone the OpenPendant repo into `app/`; run the app on a physical Android phone.
- **Audit:** find BLE service UUIDs, audio characteristic, codec handling, recording storage, any Firebase/auth/backend dependencies (see file 05 §2).
- Create `contracts/minutes.schema.json`, `openapi.yaml` stubs, `contracts/fixtures/` with 3 sample transcripts + expected JSON.
- Put `AGENTS.md` (file 08) in repo root; create `.env.example`.
- Exit: app runs; audit notes written; schema agreed by A and B.

### P1 — AI core on text (1:30–5:00) · Track B
- Implement `LLMClient`, Pydantic models from schema, zoning + extraction prompts (file 06).
- Script `eval/run_eval.py` comparing output with golden fixtures.
- Validator: utterance coverage, no gaps/overlaps, enum checks, date resolution.
- Exit: 3 fixtures produce valid JSON; coverage validator passes; first eval numbers recorded.

### P2 — ASR + pipeline + API (3:00–8:00) · Track B
- `faster-whisper` wrapper with word timestamps → utterances.
- FastAPI endpoints: health, create meeting (audio/transcript), job status, get meeting.
- Job runner with stages and progress.
- Exit: `curl` upload of a WAV returns minutes JSON in a reasonable time.

### P3 — Flutter capture + upload (1:30–7:00) · Track A
- `AudioSource`, `PhoneMicSource`, `RecordingSession`, `WavWriter` (file 05).
- Permissions, foreground service, home screen, record screen with timer + level meter.
- Drift DB with meetings; upload queue with retry; job polling.
- Exit: record 30 s on phone → file on disk → upload works against the stub/real backend.

### P4 — Viewer + minutes UI (6:00–12:00) · Track A
- Meeting list; Meeting detail with tabs: **Transcript (zones)** and **Minutes**.
- Zone colours, legend filter, tap-to-scroll, speaker chips, editable actions table, export.
- Exit: fixture JSON renders correctly; live meeting from P2 renders end to end.

### P5 — Locket source (6:00–11:00) · Track C
- Wrap the existing BLE+Opus code as `LocketBleSource` emitting PCM16 16 kHz.
- Source selector UI, health indicator, disconnect handling, "Continue on phone".
- Exit: 60 s locket recording → WAV plays back clearly → minutes generated.

### P6 — Reminders (9:00–13:00) · Track A
- `ReminderRules.compute()` pure Dart + unit tests; `ReminderScheduler` with notifications; reschedule on edit; overdue nudge.
- Exit: all rule test cases pass; real notification fires on phone (use a test deadline 3 minutes away).

### P7 — Email drafts + approval + calendar (11:00–15:00)
- Backend `draft-email` endpoint; app `DraftStateMachine`; Review & Send screen; confirm dialog; `mailto:`/intent handoff; calendar insert.
- Exit: draft generated, edited, **cannot be sent without the confirm tap** (unit test proves it), handoff opens mail app with content.

### P8 — Speakers (10:00–16:00)
- Enroll endpoint + embeddings; test-sample endpoint + screen; diarize + match in pipeline; rename + auto-enroll.
- Exit: two enrolled teammates are named correctly in a 2-person clip; score shown.

### P9 — Memory + recap (14:00–18:00)
- Chunk/embed on server; `/ask` with citations; app Ask screen; FTS5 index for offline.
- Exit: three prepared questions return correct cited answers.

### P10 — Offline tiers (16:00–20:00)
- B: Ollama client + app tier switch + demo over hotspot with internet off.
- C: model download manager, `local_slm.dart` recap from structured minutes, graceful "unavailable" state.
- Exit: B demonstrated; C either working or visibly marked Experimental.

### P11 — Thoughts + daily summary (18:00–21:00)
- Thought button + voice trigger detection; recap + research + brainstorm.
- `DailySummary` template builder + 21:00 notification; optional SLM/LLM polish.
- Exit: one thought end to end; summary notification fires.

### P12 — Freeze and ship (21:00–24:00)
- Bug bash with checklist (file 09), seed demo data, record backup video, rehearse pitch ×3, build release APK, charge phone, pack cables.

## 5. Cut lines (in order)
1. On-device SLM (keep Tier B) → 2. Thoughts research/brainstorm → 3. Daily summary polish → 4. Names vault → 5. Gmail API (keep mailto) → 6. Speaker auto-enroll → 7. Locket live (keep pre-recorded locket clip).
**Never cut:** phone recording, zone viewer, minutes, approval gate, one reminder demo.

## 6. Team allocation
| Role | People | Owns |
|------|--------|------|
| Flutter lead | 1–2 | P3, P4, P6, P7 UI |
| AI/backend lead | 1 | P1, P2, P8, P9 |
| Hardware/integration | 1 (VENOM likely) | P5, P10-B, deployment, final demo rig |
| Pitch/QA | 1 | file 09, slides, test data |
Solo? Order: P0 → P1 → P2 → P3 → P4 → P6 → P5 → P7, then whatever time allows.

## 7. Post-hackathon roadmap
v2.1 sync + accounts + encrypted storage · v2.2 streaming live captions · v2.3 battery + enclosure + LED + VAD firmware · v2.4 Slack/Notion/Calendar API integrations · v2.5 iOS · v3 team workspaces, multilingual, fine-tuned zoning model.
