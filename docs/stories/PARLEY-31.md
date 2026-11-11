# PARLEY-31 — One-press mic, everywhere, with "Nghe lại giọng tôi"

Delivery 003 (speaking method), slice 1. ACs: [spec.md § PARLEY-31](../delivery/003-speaking-method/spec.md) AC1–AC6.
Owner: "phần bật âm thanh lên để nói cũng cần rà soát lại, làm đơn giản và hiệu quả".

As a learner, I press the mic once, speak, and Parley stops when I stop talking — then I can hear myself next to the
model.

## Design
- `EndPointer` (pure): RMS levels in dBFS + elapsed time → nil or `.silence` (speech, then `quiet` s below the
  threshold), `.noSpeech` (nothing within 6 s), `.cap`. Speech = two frames in a row above max(noise floor + 12 dB,
  −50 dBFS), or any frame above −30 dBFS (speaking from the first frame never raises the floor).
- `LevelMeter` (lock-protected peak): the tap records each buffer's RMS; `MicCheck.listen` takes the peak every 100 ms.
- `MicCheck.listen(language:cap:quiet:) async -> String` replaces each screen's fixed sleep / auto-stop task; a second
  press calls `finish()`. The attempt is recorded by the `Transcriber` (`recordTo`) to
  `tmp/parley-attempts/<uuid>.m4a`; the previous one is deleted; the folder is emptied at launch and quit.
- Views: the mic buttons get a level ring (`.micLevel(mic)`), `MyVoiceButton` ("Nghe lại giọng tôi", ⌥M) after an attempt.
- Caps: word 5 s (Học tập, Phát âm của tôi), sentence `ListeningRun.listenLimit`, conversation 30 s with 2 s quiet.

## Review rounds
- Round 1 (independent): 6.0 — AC5 (permission) missing; no ring on "Nói theo", no keys on two screens, ⌥R only on
  one; the noise floor could sink for good after an empty frame; the previous card's voice replayed on the next;
  mic kept running after closing a session. Fixed (e145bb9): permission check with "Mở Cài đặt", `reset()` on every
  new card or word, dropout frames skipped and a slowly rising floor, ring only on the listening row, ⌥R / Space /
  ⌥Space, stop on close, wiring guard checks the ring and replay on every screen.

- Round 2 (same reviewer): 8.0 — "Mở Cài đặt" unreachable in Nói theo before a result; the floor rose during speech
  and cut a steady quiet voice at ~5 s; Space while the mic was busy gave a false "nothing heard". Fixed: the denied
  button before a result, the floor rises only on non-speech frames (a fan that starts at once runs to the cap — the
  trade for never cutting a long quiet sentence), `retry` ignores Space while busy, `MicCheck.ended` decides keep /
  message, tests with a real file and a 10 s quiet sentence, wiring guard for caps, per-row ring, per-card reset,
  denied button and `clearAttempts` at launch and quit.

- Round 3 (fresh reviewer, final gate): 7.5 — a skip mid-listen put "nothing heard" on the next sentence; a second
  press during the permission prompt; the model voice could be recorded; voices overlapped; image-only mic buttons.
  Fixed (5c0ee92, 86d6989): attempt ids (`reset()` makes a running attempt stale), `pending` during the prompt,
  `Speaker.stop()` before recording, "Nghe mẫu" stops the replay, Vietnamese labels, pure `finish` / `gate`.
  5c0ee92 alone broke the mic (start() refused its own pending listen) — fixed in 86d6989 and pinned in the guard.
- Re-score of round 3: **7.0** — new: a screen closed while the recognizer starts left the mic on (fixed right after,
  outside the rounds: `listen` stops a mic it opened for a stale attempt; End in Hội thoại resets; guarded).
  Shipped under the round-3 rule (requirements fit 1, security 0.5, nothing at 0); the rest is PARLEY-39.
- Scope note: AC1's "new sound lab" uses this mic in PARLEY-33.

| # | Criterion | Score |
| --- | --- | --- |
| 1 | Requirements fit | 1 |
| 2 | Tests | 0.5 (`listen()` itself has no test seam → PARLEY-39) |
| 3 | Reliability | 0.5 (open-mic bug fixed after the score) |
| 4 | Security | 0.5 (same) |
| 5 | Maintainability | 0.5 |
| 6 | UX | 1 |
| 7 | Accessibility | 1 |
| 8 | Performance | 1 |
| 9 | Docs | 0.5 |
| 10 | Delivery | 0.5 (5c0ee92 pushed with a mic that never opened) |
| | **Total** | **7.0** |

## QA
| AC | Evidence |
| --- | --- |
| AC1 one control, auto-stop, ring | `aLongQuietSentenceIsNotCut`, `EndPointerTests.stopsAfterQuietOnceSpeechWasHeard`, `pausesShorterThanQuietDoNotStop`, `speakingFromTheFirstFrameCounts`, `quietVoiceInAQuietRoomCounts`, `defaultsArePinned`, `aDropoutDoesNotTurnARoomIntoSpeech`; `make wiring-guard` (mic.listen, `.micLevel`, `MyVoiceButton` in all four screens) |
| AC2 nothing in 6 s | `nothingHeardStopsAtSixSeconds`, `oneClickIsNotSpeech`, `micPermission` (message) |
| AC3 cap | `capEndsALongTurn`, `defaultsArePinned` (5 s / 30 s / 2 s) |
| AC4 own voice, temp only | `attemptsLiveInOneTempFolderAndAreCleared`, `resetForgetsTheLastAttempt` (real file deleted), `anEmptyAttemptKeepsNoRecordingAndSaysWhy`; `make wiring-guard` (clearAttempts ×2) |
| AC5 permission | `micPermission` (status → ask / go / refuse), `refusedPermissionNeedsSettings`; `make wiring-guard` (gate, denied button before a result) |
| Skip / reset mid-attempt | `anAbandonedAttemptReportsNothing`; `make wiring-guard` (attempt ids, stale-attempt mic closed, reset on End) |
| AC6 pure rules | the tests above; `levelsInDecibels` |
| Not verified live | a real attempt with the owner's voice — the screen was locked and the sandbox app's mic prompt pending |
