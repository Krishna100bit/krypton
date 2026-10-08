# 01 — Product Requirements Document (PRD)

**Product:** Krypton v2 · **Version:** 0.1 (hackathon build) · **Owner:** VENOM (Ayush) · **Status:** Draft for build

## 1. Problem
Chronological transcripts bury decisions and actions. Restructuring a meeting manually takes 20–30 minutes. Action items lose owners and deadlines, and follow-up emails and reminders are forgotten.

## 2. Vision and goals
**Vision:** Walk out of a meeting with the minutes, owners, deadlines and reminders already done.

| Goal | Measure |
|------|---------|
| G1 Satisfy PS 04 exactly | Upload/record → zone-highlighted viewer → minutes with decisions + actions table |
| G2 Capture anywhere | Same result from phone mic, locket, or file upload |
| G3 Trustworthy automation | Every external side effect (email, calendar) needs user approval; reminders are deterministic |
| G4 Works with weak connectivity | Reminders, search and recap work offline; AI degrades gracefully across 3 tiers |
| G5 Memorable demo | Live locket recording to reminder on a phone in under 3 minutes |

## 3. Non-goals (this release)
Real-time live transcription UI, multi-language beyond English/Hinglish best-effort, team accounts/cloud sync, iOS parity, battery/enclosure design, auto-sending any email.

## 4. Personas
1. **Aarav, startup founder:** many short meetings, forgets follow-ups, wants minutes and drafts with no effort.
2. **Meera, project manager:** needs owners and deadlines per action, searchable history.
3. **Rohan, student team lead:** wants thoughts/ideas captured and a short daily wrap-up.

## 5. Feature list and priority
| ID | Feature | Priority | Tier |
|----|---------|----------|------|
| F1 | Record via phone mic | P0 | Core |
| F2 | Record via locket (BLE) | P0 | Core |
| F3 | Upload audio or transcript | P0 | Core |
| F4 | Whisper transcription | P0 | Core |
| F5 | LLM zoning into discussion/decision/action | P0 | Core |
| F6 | Zone-highlighted viewer | P0 | Core |
| F7 | Minutes: summary, decisions section, actions table | P0 | Core |
| F8 | Speaker enrollment, test sample, identification | P1 | Diff |
| F9 | Rule-based reminders (before deadlines) | P1 | Diff |
| F10 | Email drafts with human approval | P1 | Diff |
| F11 | Calendar event creation (user-confirmed) | P1 | Diff |
| F12 | Meeting memory search + recap Q&A | P1 | Diff |
| F13 | Offline recap with small language model | P2 | Stretch |
| F14 | Thoughts: capture, auto-recap, research, brainstorm | P2 | Stretch |
| F15 | Daily closing summary | P2 | Stretch |
| F16 | Important names / MoM vault | P2 | Stretch |

## 6. User stories and acceptance criteria

**US-01 Record with the phone (F1)**
As a user, I tap Record and choose "Phone", so I can capture without the locket.
- *Given* mic permission granted, *when* I tap Record, *then* a timer and level meter run and a WAV is saved when I stop.
- A foreground notification keeps recording when the screen is off (Android).

**US-02 Record with the locket (F2)**
- *Given* the locket is powered and in range, *when* I choose "Locket", *then* the app connects, shows signal/packet health, and records.
- *If* the locket disconnects, *then* the app shows a warning, keeps the partial audio, and offers "Continue on phone".

**US-03 Upload (F3)**
- *Given* a .wav/.mp3/.m4a or .txt/.vtt transcript, *when* uploaded, *then* it enters the same pipeline as a recording.

**US-04 Zone viewer (F5, F6)**
- Transcript lines are colour-coded: blue = discussion, green = decision, orange = action.
- Tapping a decision/action scrolls to and highlights its source lines. A legend filters zones.
- Each zone block shows a one-line summary and speaker chips.

**US-05 Minutes (F7)**
- Minutes show: title, date, duration, attendees, summary (≤ 6 lines), Decisions section, Actions table (task, owner, deadline, priority, status, source link).
- Cells are editable; edits persist and re-trigger reminder scheduling.
- Export to Markdown and PDF.

**US-06 Speakers (F8)**
- I can enroll a person with a 10–20 s sample and name them.
- "Test sample" records ~5 s and shows the best match with a confidence score.
- In a meeting, matched speakers show their names; unmatched show "Speaker N" and can be named afterwards (offering to enroll).

**US-07 Reminders (F9)**
- Each action with a deadline gets reminders computed by the rule table (file 07).
- *Given* airplane mode, *then* reminders still fire.
- Actions without deadlines show "Needs deadline" and are included in the daily summary.

**US-08 Email drafts with approval (F10)**
- For an action, I tap "Draft email". A draft appears with To/Subject/Body, all editable.
- The only way to send is the **Review & Send** screen with an explicit "Send" confirmation. Closing the screen leaves the draft unsent.
- Recipients must be confirmed by me; unresolved names stay blank.

**US-09 Calendar (F11)**
- "Add to calendar" opens the native calendar insert screen prefilled; the user taps Save.

**US-10 Memory and recap (F12)**
- I ask "What did we decide about pricing?" and get an answer with meeting name and timestamp citations.
- Filters: by meeting, person, zone, date range. Works over local full-text search when offline.

**US-11 Offline recap (F13)**
- With no internet and the SLM model downloaded, "Recap" of a processed meeting produces a short summary within ~30 s on a mid-range phone.

**US-12 Thoughts (F14)**
- Saying "thought: ..." in a recording, or pressing the Thought button, saves a thought with an auto-recap.
- Online: "Research this" adds a sourced summary. "Brainstorm" opens a chat seeded with the thought.

**US-13 Daily closing (F15)**
- At a set time (default 21:00) a notification summarises: meetings, decisions, actions created, due tomorrow, overdue, thoughts. Maximum 5 lines.

## 7. Non-functional requirements
| Area | Requirement |
|------|-------------|
| Latency | 10 min audio → minutes in ≤ 2 min (Tier A, GPU or fast CPU `small` model); 3-min demo clip ≤ 45 s |
| Accuracy (targets) | Action recall ≥ 80%, owner accuracy ≥ 70% on synthetic set (see file 09) |
| Reliability | App never loses a recording: audio is written to disk continuously |
| Privacy | Consent prompt before each recording; recording indicator; delete-meeting wipes audio, transcript, embeddings |
| Safety | No outbound email or calendar write without user action |
| Offline | Record, view, search, remind, and daily summary work with no network |
| Security | No API keys in the app; the app talks only to our backend; backend keys in env |
| Usability | Record start within 2 taps from the home screen |

## 8. Success metrics (for the pitch)
Time from stop → minutes; action recall/owner accuracy on test set; number of manual steps saved (from ~25 min to ~1 min review); reminder correctness (100% of rule test cases).

## 9. Risks
| Risk | Mitigation |
|------|-----------|
| BLE instability | Phone mic source and upload fallback; pre-recorded locket clip |
| Weak speaker ID in noisy rooms | Show confidence, allow rename, use enrollment of 15–20 s |
| SLM quality | Restrict to recap over structured minutes; always keep Tier A/B fallback |
| Scope creep | Cut lines in file 04; freeze at hour 21 |
| Repo surprises (auth, Firebase, old backend) | Audit in P0, stub out dependencies |

## 10. Release criteria
All P0 stories pass; at least three P1 stories pass; backup demo video recorded; every external side effect is gated by explicit user confirmation.
