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

## QA
| AC | Evidence |
| --- | --- |
| AC1 one control, auto-stop, ring | `EndPointerTests.stopsAfterQuietOnceSpeechWasHeard`, `pausesShorterThanQuietDoNotStop`, `speakingFromTheFirstFrameCounts`, `quietVoiceInAQuietRoomCounts`, `defaultsArePinned`, `aDropoutDoesNotTurnARoomIntoSpeech`; `make wiring-guard` (mic.listen, `.micLevel`, `MyVoiceButton` in all four screens) |
| AC2 nothing in 6 s | `nothingHeardStopsAtSixSeconds`, `oneClickIsNotSpeech`, `micPermission` (message) |
| AC3 cap | `capEndsALongTurn`, `defaultsArePinned` (5 s / 30 s / 2 s) |
| AC4 own voice, temp only | `attemptsLiveInOneTempFolderAndAreCleared`, `resetForgetsTheLastAttempt` |
| AC5 permission | `micPermission` (status → ask / go / refuse) |
| AC6 pure rules | the tests above; `levelsInDecibels` |
| Not verified live | a real attempt with the owner's voice — the screen was locked and the sandbox app's mic prompt pending |
