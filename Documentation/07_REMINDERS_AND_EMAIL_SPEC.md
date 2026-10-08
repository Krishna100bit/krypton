# 07 — Reminders, Calendar, Email Drafts, Daily Summary

Principle (D5, D6): **the LLM proposes, deterministic rules decide, and the human approves every outbound action.**

## 1. Reminder engine (hardcoded, offline)

### 1.1 Inputs and outputs
Input: `deadline` (local DateTime, nullable), `priority`, `now`, `quietHours` (default 22:00–07:00), `morningTime` (default 09:00).
Output: sorted list of `ReminderPlan{fireAt, kind, label}`.

### 1.2 Rule table
| Condition | Reminders |
|-----------|-----------|
| No deadline | None. Mark "Needs deadline"; include in daily summary; one nudge the next morning at `morningTime` |
| Deadline − now < 2 h | One reminder at deadline − 15 min (if still in the future) |
| Priority HIGH | deadline − 24 h, deadline − 3 h, deadline − 30 min |
| Priority MEDIUM | deadline − 24 h, deadline − 2 h |
| Priority LOW | Morning of deadline day at `morningTime` (if before the deadline), else deadline − 2 h |
| Deadline more than 3 days away (any priority) | Add a "heads-up" at deadline − 3 days at `morningTime` |
| Overdue and open | Daily nudge at `morningTime` until done or snoozed |

Post-processing, in this order:
1. Drop any `fireAt` ≤ now + 1 minute.
2. **Quiet hours:** if `fireAt` falls inside quiet hours, move it to the next `morningTime` **if that is still before the deadline**; otherwise move it to deadline − 30 min; if that is also quiet and the deadline is within quiet hours, keep the original (never silently drop a high-priority reminder).
3. Merge reminders within 10 minutes of each other (keep the later one).
4. Cap at 5 reminders per action.

### 1.3 Dart skeleton (`domain/reminder_rules.dart`)
```dart
enum Priority { high, medium, low }

class ReminderPlan {
  final DateTime fireAt;
  final String kind;   // 'heads_up' | 't_minus' | 'morning' | 'overdue' | 'final'
  final String label;  // human-readable, shown in the action detail
  const ReminderPlan(this.fireAt, this.kind, this.label);
}

List<ReminderPlan> computeReminders({
  required DateTime? deadline,
  required Priority priority,
  required DateTime now,
  TimeOfDay quietStart = const TimeOfDay(hour: 22, minute: 0),
  TimeOfDay quietEnd   = const TimeOfDay(hour: 7,  minute: 0),
  TimeOfDay morning    = const TimeOfDay(hour: 9,  minute: 0),
}) { /* pure function: no Flutter plugins, no clock access */ }
```
`now` is always injected so tests are deterministic.

### 1.4 Scheduler
- `ReminderScheduler.sync(action)`: cancel existing reminders for the action → compute → insert rows → `zonedSchedule` each (`androidScheduleMode: exactAllowWhileIdle`) with a stable notification id (`hash(actionId + kind)`).
- Triggers for `sync`: action created, edited, marked done (cancel all), snoozed (+1 h / tomorrow morning).
- Notification actions: **Done**, **Snooze 1h**, **Open**. Tapping opens the action detail.
- On app start and after boot: re-sync all open actions (idempotent).
- Channels: `reminders` (high importance), `daily_summary` (default).
- Permission flow: request notifications; on Android 12+ check exact alarm permission and deep link to settings if missing; show an in-app banner if disabled.
- The reminders list is also visible in-app so the feature is demonstrable even if the OS blocks notifications.

### 1.5 Required unit tests (all must pass before demo)
| # | now | deadline | priority | Expected |
|---|-----|----------|----------|----------|
| 1 | Mon 10:00 | Fri 17:00 | high | Thu 17:00, Fri 14:00, Fri 16:30, plus heads-up Tue 09:00 (>3 days) |
| 2 | Mon 10:00 | Tue 12:00 | medium | Mon 12:00 (24 h earlier = Mon 12:00), Tue 10:00 |
| 3 | Mon 10:00 | Mon 11:30 | high | Single: Mon 11:15 |
| 4 | Mon 10:00 | Wed 08:00 | medium | T−24h = Tue 08:00 → fine; T−2h = Wed 06:00 is quiet → moved to Wed 07:30 |
| 5 | Mon 10:00 | null | any | [] and `needsDeadline` flag |
| 6 | Mon 10:00 | Sun (past) | any | [] and overdue nudge schedule |
| 7 | Mon 23:00 | Tue 09:00 | high | T−24h dropped (past); T−3h = Tue 06:00 is quiet and next morning 09:00 is not before the deadline → moved to deadline − 30 min = Tue 08:30, which merges with the T−30m reminder → single Tue 08:30 |
| 8 | Mon 10:00 | Mon 10:30 | low | Single reminder Mon 10:15 (the "< 2 h" rule overrides priority) |
| 9 | any | any | any | No two reminders within 10 min; ≤ 5 total |
If you change the rules, update the expected values here and in the test file together, and keep these scenarios.

## 2. Calendar (human-confirmed)
- "Add to calendar" button on an action → `add_2_calendar` opens the native insert screen prefilled (title = task, start = deadline − 30 min or deadline, notes = meeting link/quote). The user taps Save.
- Optional upgrade: Google Calendar API insert after an explicit confirm dialog showing the event details.
- Never create events in the background.

## 3. Email drafts with human-final approval

### 3.1 Flow
1. User taps **Draft email** on an action (or "Draft follow-up for this meeting").
2. App calls `/v1/actions/{id}/draft-email` (Tier A/B) or builds a **template draft** locally if offline.
3. Draft saved as `GENERATED`. UI opens the draft editor (To, Cc, Subject, Body — all editable).
4. User taps **Review & Send** → full-screen preview, "To" recipients chips, attachments (none by default).
5. User taps **Send** → confirmation dialog: "Send this email to *name@example.com*?" with **Cancel / Send**.
6. Only the Send button inside this dialog sets `APPROVED` and calls the handoff.

### 3.2 State machine (`domain/draft_state_machine.dart`)
States: `GENERATED, EDITED, PENDING_APPROVAL, APPROVED, SENT, FAILED, DISCARDED`.
Transitions: as in file 02 §3.3. Any edit after `PENDING_APPROVAL` returns to `EDITED` (approval is invalidated by changes).

### 3.3 Invariants (write tests for each)
1. `sendHandoff()` throws unless `draft.state == APPROVED` **and** the approval token was minted by `ConfirmSendDialog` in the same session.
2. Approval token expires after 60 seconds and is single-use.
3. Editing any field after approval resets the state.
4. The backend `draft-email` endpoint returns text only; it has no send capability and no mail credentials.
5. Recipients are never auto-filled from an LLM guess: `suggested_to` is shown as chips labeled "Suggested — confirm"; unconfirmed addresses block the Send button.
6. No background job, notification action, or deep link can trigger send.
7. Logging never records the body of drafts.

### 3.4 Handoff options
| Option | How | Pros | Cons |
|--------|-----|------|------|
| **Default: mail client** | `mailto:` URL or Android `ACTION_SENDTO` with subject/body → user's mail app opens prefilled; user presses Send there | No OAuth, offline-friendly, human-final by nature | Two taps; long bodies may truncate in some clients |
| Upgrade: Gmail API draft | `users.drafts.create` (scope `gmail.compose`), then open the draft in Gmail | Real Gmail draft | OAuth setup; the scope technically allows sending, so the code must only call `drafts.create` |
| Upgrade: Gmail API send | `users.messages.send` after the confirm dialog | One-tap send | Highest risk; build last or skip |
Recommended for the hackathon: default option, with the in-app approval flow in front of it so the "human permission" story is visible to judges.

### 3.5 Draft generation prompt
```
Write a short, polite follow-up email for this action item from a meeting.
Context: meeting title, date, action task, owner, deadline, relevant decision (if any).
Rules: max 120 words; plain text; start with a greeting using the recipient's name only if provided; include the task and deadline once; no invented facts, no promises beyond the task; end with a thanks and the sender's first name placeholder {sender_name}.
Return JSON: {"subject": "...", "body": "..."}
```
Offline template: `Subject: Follow-up: {task}` / body with fixed text and fields filled from the action.

## 4. Task "automation" scope (what is automatic and what is not)
| Step | Automatic? |
|------|-----------|
| Extract tasks, owners, deadlines | Yes (LLM) |
| Compute reminder schedule | Yes (rules) |
| Fire notifications | Yes (local) |
| Create calendar event | **No**, user saves in the calendar screen |
| Create email draft text | Yes (text only) |
| Send email | **No**, user approves explicitly |

## 5. Names and notes vault (stretch)
Store important names/phrases flagged by the user or extracted as `names_mentioned`; searchable list with the meeting they came from. No sensitive categories auto-tagged.

## 6. Daily closing summary

### 6.1 Template (deterministic)
```
Today you had {n_meetings} meeting(s) · {n_decisions} decision(s) · {n_actions} new action(s).
Due tomorrow: {due_tomorrow_list or "nothing"}.
Overdue: {overdue_count}.   Needs a deadline: {nodeadline_count}.
Thoughts captured: {n_thoughts}.
Top decision: {top_decision}.
```
Maximum 5 lines. `top_decision` = highest-priority/most recent decision. Skip lines that are zero except the first.

### 6.2 Scheduling
Local daily notification at the user's time (default 21:00); tapping opens a Summary screen with the same text plus quick links. Content is generated at fire time from the DB (compute a fresh summary when the app opens, and pre-compute when possible). Optional "polish" with LLM/SLM must not add facts; if it fails, the template is shown.
