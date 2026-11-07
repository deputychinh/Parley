# 001 Learning suite — verification (v0.2.0 candidate)

Run on `main` (2026-11-08), macOS 27, Apple Silicon, machine load average 29–54 during the run.

## Gates

| Check | Command | Result |
| --- | --- | --- |
| Offline guard, settings guard, release build (warnings = errors), 154 tests | `make ci` | green |
| Real speech recognition + translation | `make pipeline` | "Good morning, everyone. Let's start the meeting." → "Chào buổi sáng mọi người. Hãy bắt đầu cuộc họp." |
| W1 progress aggregation (3 years) | `make bench` | 1.1 ms (target < 20 ms) |
| W2 clip open + seek | `make bench` | 17 ms (target < 300 ms) |
| W3 on-device coach | `make ai-eval` | conversation 5/8 (62 %, ADR threshold 60 %), p50 1.9 s (target < 8 s); writing 4/6 planted mistakes in 6.2 s |
| Owner data untouched | `ls -lT ~/Documents/Parley`, `defaults read com.david.parley` before/after shot runs | identical (since PARLEY-13/16; see the correction in status.md) |

## Acceptance criteria

| AC | Evidence | Item (score) |
| --- | --- | --- |
| AC1.1–1.3 | `make ci`; `DataSafetyTests`, `SandboxDefaultsTests`; `make shot` / `make shot-test` (sandbox app) | PARLEY-1 (8.5), 9 → 10 (9.5), 13 → 16 (9.0) |
| AC2.1–2.5 | `XPWiringTests`, `ActivityStoreTests`, `StoreFileTests`; `progress.png`, `progress-empty.png`, `progress-narrow.png` | PARLEY-2 (8.0), 11 (9.5) |
| AC3.1–3.5 | `ClipTests`, `WordDiffTests`, `ListeningRunTests`, `BenchSeededClipTests`; `listening*.png` | PARLEY-3 (7.5), 12 (8.5) |
| AC4.1–4.5 | `CoachTests`, `ConversationModelTests`, `ModelTimeoutTests`; `make ai-eval`; `conversation*.png` | PARLEY-4 (7.5), 14 → 17 (9.0) |
| AC5.1–5.3 | `WritingRulesTests`, `WritingStoreTests`; `make ai-eval`; `writing*.png` | PARLEY-5 (9.0) |
| AC6.1 (cut: bundled only), 6.2, 6.3 | `ReadingRulesTests`, `ReadingQuizTests`, `ReadingXPPerDayTests`; `reading*.png` | PARLEY-6 → 18 (in review) |
| AC7.1–7.2 | `CSVTests`, `VocabTransferTests`, `TransferEdgeTests`, `AnkiAndRoundTripTests`; `vocabulary-import.png` | PARLEY-7 (8.0) |
| AC8.1 | `ReminderTests`, `GoalMetCallbackTests`; `settings.png`; delivery checked by hand (needs permission) | PARLEY-8 (8.5) |

## Known gaps (backlog)

- PARLEY-15 — debt from final review rounds (CSV ties/BOM, reminder footer/time zone, mic edge cases, guard bypasses, session reset after cancel).
- PARLEY-19 — AI-written reading passages (cut for v0.2.0).
- Screenshots `reading*.png` and `conversation*.png` predate the last UI changes (interpreter toolbar hidden on learning screens): the display was locked when they should have been retaken.
- Mic paths (shadowing, conversation by voice, pronunciation) and notification delivery are verified by code review only; they need a person at the Mac.
