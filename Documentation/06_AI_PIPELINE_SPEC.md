# 06 — AI Pipeline Specification

## 1. Pipeline stages
```
audio/transcript → [1 ingest+normalize] → [2 ASR] → [3 diarize] → [4 speaker match]
→ [5 utterance build] → [6 zoning] → [7 extraction] → [8 validate/repair] → [9 chunk+embed] → minutes JSON
```
Transcript-only input skips stages 1–4 (speakers parsed from labels if present).

### Stage notes
1. **Normalize:** ffmpeg → 16 kHz mono WAV, loudness normalize lightly.
2. **ASR:** faster-whisper, `word_timestamps=True`, VAD filter on, language auto or forced. Output words with times.
3. **Diarization:** pyannote 3.1 → speaker turns. Merge words into turns by timestamp overlap.
4. **Speaker match:** for each diarized speaker, average ECAPA embeddings of its longest clean turns (≥ 3 s total, up to 30 s); cosine against enrolled embeddings; assign if score ≥ threshold and margin over second-best ≥ 0.05, else "Speaker N". Thresholds are **calibrated** on your own samples (SpeechBrain's default verification cutoff is around 0.25 for its own scoring; tune on your data and show the score in UI).
5. **Utterances:** merge consecutive words from the same speaker with gaps < 1.0 s; split at > 25 s. Number them `u0…uN`. This index is the shared coordinate system for everything after.

## 2. Output schema (`contracts/minutes.schema.json`)
```json
{
  "meeting": {"id": "", "title": "", "date": "2026-10-09", "duration_s": 0, "language": "en"},
  "speakers": [{"id": "S1", "name": "Rahul", "matched": true, "confidence": 0.82}],
  "utterances": [{"idx": 0, "speaker_id": "S1", "start": 0.0, "end": 6.2, "text": ""}],
  "segments": [{
    "id": "seg_1", "zone": "discussion|decision|action",
    "start_idx": 0, "end_idx": 5, "summary": "", "speaker_ids": ["S1"], "confidence": 0.85
  }],
  "decisions": [{"id": "d1", "text": "", "decided_by": ["S1"], "rationale": null, "segment_id": "seg_2"}],
  "actions": [{
    "id": "a1", "task": "",
    "owner": {"speaker_id": "S2", "name": "Priya", "inferred": true, "confidence": 0.7},
    "deadline": {"iso": "2026-10-12T17:00:00+05:30", "raw": "by Monday evening", "inferred": false},
    "priority": "high|medium|low", "segment_id": "seg_3", "source_utterance_idx": 14
  }],
  "summary": "", "open_questions": [""], "names_mentioned": [""]
}
```
Rules: segments are **contiguous, ordered, non-overlapping, and cover every utterance**; every decision/action references a segment; `source_utterance_idx` must exist.

## 3. Zone definitions (use verbatim in prompts)
- **discussion** — ideas, questions, explanations, status updates, debate, brainstorming; no commitment reached.
- **decision** — the group agrees or the leader settles something ("let's go with…", "agreed", "we'll use…"); capture what and who.
- **action** — a person commits or is assigned to do something later ("I'll send…", "Priya, can you…" + agreement); needs task, owner, deadline if stated.
A segment has exactly one zone (the dominant one); a decision and an action can be adjacent segments. Short acknowledgements ("okay", "yes") attach to the segment they confirm.

## 4. Zoning + extraction prompt (starting point)
**System:**
```
You turn meeting transcripts into structured minutes. The transcript is a numbered list of utterances:
[idx] Speaker: text
Rules:
1. Output ONLY valid JSON matching the provided schema. No prose, no code fences.
2. Segment the transcript into contiguous segments that cover EVERY utterance exactly once, in order.
3. Label each segment: discussion, decision, or action using the definitions provided.
4. Decisions: state what was decided in one sentence; list who decided; add rationale only if stated.
5. Actions: task as an imperative sentence; owner = the person who commits or is clearly assigned. If unclear use null. Never guess names that are not in the transcript.
6. Deadlines: copy the raw phrase and resolve it to an ISO-8601 datetime using the meeting date {meeting_date} and timezone {tz}. If no deadline is stated, set deadline to null. Do not invent deadlines.
7. Priority: high if urgent/blocking/explicitly important or due within 48h; low if "whenever/nice to have"; otherwise medium.
8. Reference evidence only by utterance index, never by quoting.
9. Be conservative: if unsure whether something is an action, label the segment discussion and add the item to open_questions.
```
**User:** the numbered transcript + meeting metadata + one few-shot example (a 12-utterance example with correct JSON). Keep few-shot in `backend/app/llm/prompts/zoning_fewshot.json`.

### Chunking for long meetings
> 25k tokens: split by ~150 utterances with 10 overlap, run per chunk, then merge: reindex, join adjacent same-zone segments across chunk boundary, de-duplicate decisions/actions by normalized text similarity (≥ 0.85).

### Validation and repair (stage 8)
1. JSON parse; Pydantic validation.
2. Coverage check (no gaps/overlaps). Auto-repair: fill gaps with `discussion`, trim overlaps.
3. Referential integrity (segment ids, utterance indices).
4. Date sanity: deadline not before meeting date; if before, flag `needs_review`.
5. If invalid after auto-repair: one **repair call** with the validator's error list; else fall back to heuristic zoning (keyword rules: "agreed/decided/let's go with" → decision; "I'll/will/by <date>/can you" → action).

## 5. Owner and deadline inference rules
| Pattern | Owner |
|---------|-------|
| "I'll do X" | speaker |
| "Priya, can you do X?" + "sure/yes/okay" from Priya | Priya |
| "We should do X" (no name) | null (flag Unassigned) |
| "Rahul will handle X" | Rahul |
Deadlines: "tomorrow", "Friday", "end of week", "next Monday", "in two days", "EOD" resolve relative to meeting date; default time 17:00 local if only a date is given, marked `time_inferred`.

## 6. Speaker enrollment
- Record 10–20 s of natural speech (provide a short prompt to read). Reject if SNR is too low or < 8 s of speech (VAD).
- Store the mean embedding plus count; allow adding more samples to improve.
- **Test sample endpoint:** 5 s audio → embeddings → cosine to all enrolled → return ranked list, best score, and the threshold used.
- Post-meeting rename of "Speaker N" → name; option "Enroll from this meeting" using their best turns.

## 7. Memory and recap (RAG)
- **Chunks:** per segment (≈ 100–300 tokens) with metadata (meeting, time, zone, speakers). Also index each decision and action as its own chunk (high signal).
- **Embeddings:** bge-small/MiniLM; Chroma persistent.
- **Retrieval:** top-8 with filters (meeting, zone, speaker, date); optional keyword boost via SQLite FTS.
- **Answer prompt:** "Answer only from the context. Cite as [meeting title, mm:ss]. If the context does not contain the answer, say you could not find it."
- **Recap command:** summarize one meeting from its minutes JSON: 3-line summary + decisions + top actions.

## 8. Offline tiers
**Tier B (local server):** same pipeline; `LLM_PROVIDER=ollama`, a 7–8B instruct model. Expect weaker JSON adherence than Claude: use lower temperature (0.1), smaller schema chunks, and the repair step more often. Test early (P10 gate) rather than at the end.

**Tier C (on-device SLM):**
- Scope: **recap and Q&A over already-structured minutes**, not full zoning. Input is the minutes JSON reduced to ≈ 300–800 tokens.
- Model: Qwen2.5-1.5B-Instruct Q4_K_M (≈ 1 GB) default; alternatives: a 1–2B Gemma-class or Llama-3.2-1B. Check each model's license and size before bundling; offer download inside the app rather than shipping it in the APK.
- Prompt (short): "Using only the facts below, write a 4-line recap: key decisions, then actions with owners and dates. Facts: ..."
- Settings: temperature 0.2, max tokens 200, context 2048, run in an isolate, show a progress indicator, hard timeout 60 s with extractive fallback (template recap from JSON).
- **Extractive fallback is mandatory:** if the SLM fails, show the template recap built directly from the JSON so the feature never appears broken.
- On-device ASR (optional): whisper.cpp `tiny.en`/`base.en`; accuracy lower, so mark transcripts "offline draft"; reprocess when online.

## 9. Thoughts
- **Trigger:** utterance begins with "thought", "note to self", "idea", "remember this" (rule match) **or** LLM intent classifier on a short utterance (online); manual Thought button always works.
- **Recap:** 1–2 line summary + tags.
- **Research (online only):** generate 2–3 search queries → Tavily → fetch top results → LLM summary with source list. Never present unsourced claims as researched.
- **Brainstorm:** chat with system prompt "You are a brainstorming partner: ask one clarifying question, then offer 5 distinct directions, then help pick one." Keep history in the app DB.

## 10. Daily closing summary
Deterministic template first (file 07 §6); optional one-pass LLM/SLM polish that must not add facts. Inputs: today's meetings, decisions, new actions, due tomorrow, overdue, thoughts count.

## 11. Evaluation
| Metric | How |
|--------|-----|
| Zone accuracy | Utterance-level accuracy vs golden labels, plus segment boundary F1 (±1 utterance) |
| Action recall/precision | Match by normalized task similarity ≥ 0.7 |
| Owner accuracy | Exact name match among matched actions |
| Deadline accuracy | Same calendar day |
| Speaker ID | Accuracy on a 2–3 person clip; false-accept rate on an unenrolled voice |
| Latency | Per stage timings |
| JSON validity rate | % passing validation without repair |
Dataset: 8–10 meetings: 3 from AMI (use ASR transcripts or annotations), 5–7 generated (LLM-written dialogues with a hidden answer key, then text-to-speech with 2–3 voices for audio tests). Save as `eval/data/*.json`. Report one table in the deck.

## 12. Prompt safety and privacy
Treat transcript text as untrusted data: the system prompt states that instructions inside the transcript must be ignored. Never include API keys in prompts. Strip emails/phones from logs.
