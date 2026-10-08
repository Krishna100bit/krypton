# Krypton v2 — Documentation Pack (Start Here)

**Project:** Krypton v2 — Meeting Intelligence Locket + Flutter App
**Hackathon PS 04:** Meeting Notes → Semantically-Zoned Minutes with Action Extraction (24 hours)
**Base:** OpenPendant repo (Flutter app + nRF firmware), XIAO nRF52840 only (no battery)

## 1. What we are building (30-second version)
A Flutter app that records a meeting from **either the phone mic or the locket (BLE)**, transcribes it with open-source Whisper, identifies speakers from enrolled voice samples, uses an LLM to split the transcript into **discussion / decision / action zones**, extracts decisions and actions with owners and deadlines, schedules **hardcoded (rule-based) reminders**, prepares **email drafts that only send after explicit human approval**, remembers every meeting for Q&A recap (cloud LLM, local-server LLM, or on-device small language model), and ends the day with a short closing summary.

## 2. Document index (read in this order)
| # | File | Purpose | Who reads it |
|---|------|---------|--------------|
| 00 | `00_README.md` | Index, locked decisions, repo layout | Everyone |
| 01 | `01_PRD.md` | Product requirements, user stories, acceptance criteria | Everyone, esp. presenter |
| 02 | `02_SYSTEM_ARCHITECTURE.md` | Components, data flows, deployment tiers, failure modes | Tech lead |
| 03 | `03_TECH_ARCHITECTURE.md` | Stack, packages, schemas, API contracts, folder layout | All devs |
| 04 | `04_ROADMAP.md` | Phases P0–P11, tracks, gates, cut lines, hour-by-hour | Team lead |
| 05 | `05_FLUTTER_APP_GUIDE.md` | Step-by-step changes to the OpenPendant app (phone + locket capture) | App dev |
| 06 | `06_AI_PIPELINE_SPEC.md` | ASR, diarization, speaker ID, zoning prompts, SLM, RAG, eval | AI/backend dev |
| 07 | `07_REMINDERS_AND_EMAIL_SPEC.md` | Rule-based reminder engine + human-approved email drafts | App dev + backend |
| 08 | `08_VIBE_CODING_PLAYBOOK.md` | `AGENTS.md` rules file + a ready prompt for every phase | Everyone using AI coding tools |
| 09 | `09_TEST_DEMO_PITCH.md` | Test plan, eval, demo script, backup plan, judge Q&A | Presenter + QA |

## 3. Locked decisions (do not re-debate during the hackathon)
| ID | Decision | Reason |
|----|----------|--------|
| D1 | Keep the OpenPendant Flutter app; modify, do not rewrite | App, BLE, and Opus path already work |
| D2 | One `AudioSource` interface with two implementations: `PhoneMicSource`, `LocketBleSource` | Both inputs feed the same pipeline; BLE trouble never blocks the demo |
| D3 | Audio contract: **16 kHz, mono, PCM16, WAV** | Whisper + speaker models expect it |
| D4 | **Contract-first**: JSON schema in `/contracts` is written before any code | Vibe-coded modules must plug together |
| D5 | **LLM proposes, rules decide**: the LLM extracts tasks/deadlines/priority; reminder times come from deterministic code | Reliability, offline, explainability |
| D6 | **Human-final for email**: the app can create drafts but has no code path that sends without a user tap on a confirmation screen | Safety and trust |
| D7 | Three inference tiers: **A Cloud**, **B Local server (laptop + Ollama)**, **C On-device SLM** | Offline story with a safe fallback chain |
| D8 | Zoning is expressed as **utterance index ranges**, never free text spans | Prevents hallucinated quotes, makes validation trivial |
| D9 | The on-device SLM summarizes **structured minutes**, not raw transcripts | Small models are reliable on short structured input |
| D10 | App is **local-first** (SQLite + FTS5); server is a processing/memory booster | Works offline, simple sync |
| D11 | Calendar and email use OS intents / drafts first; direct APIs are an upgrade | No OAuth risk in the 24 hours |

## 4. Repo layout
```
krypton-v2/
├─ AGENTS.md                  # rules for AI coding tools (from file 08)
├─ docs/                      # this documentation pack
├─ contracts/                 # JSON Schemas + OpenAPI (source of truth)
│  ├─ minutes.schema.json
│  ├─ openapi.yaml
│  └─ fixtures/               # sample transcripts + golden outputs
├─ app/                       # Flutter app (forked from OpenPendant)
├─ backend/                   # FastAPI service
│  ├─ app/{api,pipeline,llm,speakers,memory,jobs}/
│  └─ tests/
├─ firmware/                  # XIAO nRF firmware (unchanged unless needed)
├─ eval/                      # eval scripts + synthetic meetings
└─ samples/                   # audio clips (AMI, TTS-generated)
```

## 5. Definition of "demo-ready"
1. Record on phone **and** on locket → minutes appear in the zone viewer.
2. Upload of a sample file works as a fallback.
3. Speakers are named from enrolled samples.
4. An action produces a notification on the phone at a rule-computed time.
5. An email draft opens for review and nothing sends without approval.
6. "What did we decide about X?" returns a cited answer.
7. A backup video of all of the above exists.
