# 05 — Flutter App Guide: Adding Phone-Mic and Locket Capture

Goal: one app, two inputs (phone mic, locket), one pipeline. Do the steps in order; each ends with a check.

## 1. Setup
1. Clone the OpenPendant repo into `app/`, run `flutter doctor`, pin the Flutter version the repo uses (check `.fvm`, `pubspec.yaml` `environment`).
2. Build and run on a **physical Android phone** (BLE and mic do not work properly on emulators).
3. Make a branch `feat/dual-capture`. Commit after every step.

## 2. Audit the existing app (write findings in `docs/audit.md`)
Run these searches in the repo and note file paths:
| Question | Search hint |
|----------|-------------|
| Where is BLE scanning/connecting? | `flutter_blue_plus`, `FlutterBluePlus`, `BluetoothDevice`, `connect(` |
| Service/characteristic UUIDs? | `Guid(`, `serviceUuid`, `19b10000` (UUID prefix common in Omi-derived firmware; **verify against your firmware**) |
| Codec handling? | `opus`, `codec`, `decode`, `pcm` |
| Where is audio stored/streamed? | `wav`, `File(`, `socket`, `websocket`, `stream` |
| Backend/auth dependencies? | `firebase`, `auth`, `http.post`, `api_base_url`, `.env` |
| State management? | `Provider`, `ChangeNotifier`, `Riverpod`, `Bloc` |
Deliverable: a list of the 5–10 files you will touch, and a list of external services to stub out.
**Check:** you can explain, in 5 lines, how a BLE audio packet becomes playable audio today.

## 3. Strip or stub dependencies
- If the app requires login/Firebase/Omi cloud on startup, add a `DEV_MODE` flag that skips auth and removes cloud calls. Do not delete code you are unsure about; gate it.
- Point all network calls to a single `ApiClient` with base URL from settings.
**Check:** app launches to your own Home screen with no login.

## 4. Define the audio contract and abstraction
Create `lib/audio/audio_source.dart` (interface in file 03). Contract: PCM16, 16 kHz, mono, little-endian; the source handles resampling/decoding.
Create `lib/audio/recording_session.dart`:
- Takes an `AudioSource`, opens a `WavWriter`, appends bytes as they arrive (**write to disk continuously**, not at the end).
- Exposes `elapsed`, `level` (RMS), `state` (idle/recording/paused/stopped), `sourceHealth`.
- On stop: patches WAV header sizes, creates the meeting row (`status=recorded`).
- On app restart: scans for unfinalized WAVs and offers recovery.
**Check:** unit test with a fake source writing 3 s of sine wave produces a valid, playable WAV.

## 5. PhoneMicSource
- Package: `record`. Use the streaming API with `encoder: pcm16bits`, `sampleRate: 16000`, `numChannels: 1`.
- Permissions: request `RECORD_AUDIO` at first use; explain why.
- Android: start `flutter_foreground_task` with a microphone foreground-service type so recording survives screen-off.
- Consider disabling aggressive noise suppression/AGC if audio sounds pumped (Whisper prefers natural audio).
**Check:** 30 s recording plays back clean; screen-off recording works.

## 6. LocketBleSource (wrap, don't rewrite)
1. Move the repo's existing "connect + subscribe + decode" logic behind `LocketBleSource implements AudioSource`.
2. Output: decoded PCM from the Opus frames. If the repo decodes to 16 kHz mono already, pass through; otherwise resample.
3. Health: emit `connected`, `rssi`, `droppedFrames` (detect gaps via packet index if the firmware sends one), `lastPacketAt`.
4. Reconnect: exponential backoff up to 10 s, keep the same `RecordingSession` open; insert silence for gaps up to 2 s, otherwise mark a gap.
5. Foreground service for BLE as well; request `BLUETOOTH_SCAN` / `BLUETOOTH_CONNECT` (Android 12+).
**Check:** record 60 s from the locket, play the WAV, speech is intelligible; unplug the locket mid-recording and the app shows the warning and keeps the audio.

## 7. Source selector and Record screen
- Home: big Record button plus a segmented control **Phone | Locket | Auto** (Auto = locket if connected else phone).
- Record screen: timer, level meter, source badge, health row (BLE signal, dropped frames), pause/stop, **consent banner**, bookmark button ("mark this moment").
- Locket pairing sheet: scan, pick device, remember last device.
**Check:** switching source before recording works; the same pipeline produces a meeting row for both.

## 8. Local database (drift)
Implement tables from file 03 (start with `meetings`, `utterances`, `segments`, `actions`; add the rest as phases need them). Generate DAOs and repositories. Add FTS5 `chunks_fts`.
**Check:** insert a fixture minutes JSON and render it without network.

## 9. Upload + job polling
- `UploadQueue`: stores pending uploads, retries with backoff, resumes after restart, one at a time.
- `POST /v1/meetings` (multipart) → poll `/v1/jobs/{id}` every 2 s → on `ready` fetch minutes → write to DB → index FTS5 → schedule reminders.
- Show per-meeting status chips: Recorded · Uploading · Processing (stage) · Ready · Failed (Retry).
**Check:** airplane mode → recording saved as "Recorded"; reconnect → auto uploads.

## 10. Screens (build in this order)
1. Home (record, recent meetings, today's actions) 2. Record 3. Meetings list 4. **Meeting detail: Zone viewer** 5. **Minutes** 6. Actions 7. Speakers (enroll, test) 8. Drafts + Review & Send 9. Ask 10. Thoughts 11. Settings (server URL, tier, quiet hours, daily summary time, model download).

### Zone viewer spec
- List of utterance rows grouped into segment blocks; block header shows zone icon, one-line summary, time range, speaker chips.
- Colours (use theme tokens): discussion = blue, decision = green, action = orange. Never rely on colour alone: also show an icon and label.
- Tap decision/action chip in Minutes → `scrollToUtterance(idx)` with a 2 s highlight.
- Legend toggles filter zones. Search within transcript.

## 11. Manifest and permissions (Android)
`RECORD_AUDIO`, `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`, `POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM` (or `USE_EXACT_ALARM` if eligible), `RECEIVE_BOOT_COMPLETED`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MICROPHONE`, `FOREGROUND_SERVICE_CONNECTED_DEVICE`, `INTERNET`. Declare queries for mail/calendar intents. iOS parity is out of scope.

## 12. Pitfalls checklist
- BLE MTU/throughput: request a larger MTU; log packet rates.
- Opus frame size mismatches cause "robot" audio; check sample rate and frame duration.
- Doze mode can delay notifications; use exact alarms and tell the user to disable battery optimization for the demo phone.
- Large WAVs: 16 kHz mono PCM16 ≈ 1.9 MB/min; compress to FLAC/Opus for upload only if bandwidth is a problem.
- Keep the old OpenPendant features that still work; hide what you do not need behind a settings flag.
- Do not request more permissions than needed on first launch; ask in context.

## 13. Definition of done (app dual capture)
Both sources produce identical meeting rows and WAV format; consent shown; recording survives screen-off; interrupted recording recoverable; upload queue survives restarts.
