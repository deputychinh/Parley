# PARLEY-17 — A model timeout that never waits (continues blocked PARLEY-14)

## Changes
- `Timeout.swift`: one helper, `modelTimeout(seconds, work)`, replaces `withTimeout` (Writing) and
  `mainActorTimeout` (Conversation). A continuation is resumed by whichever comes first — the work, the timer
  (`TimeoutError`) or the caller's cancellation (`CancellationError`) — so it returns on time even when the model
  ignores cancellation; the late work is cancelled and its result discarded. `TimeoutError` lives with it.
- `ModelCoach` resets its session after a timeout (`sessionResets`), so the next turn never meets a busy session.

## Evidence
| Finding | Evidence |
| --- | --- |
| returns on time with non-cancellable work | `ModelTimeoutTests.workThatIgnoresCancellationStillTimesOutOnTime` (0.1 s timeout, work runs 2 s, returns < 1 s) |
| caller cancellation ≠ timeout | `callerCancellationIsNotATimeout` |
| session reset | `coachResetsItsSessionAfterATimeout` |
| writing / reading use it | `timeoutFailsSlowWork`, `noRetryAfterATimeout` |

## Review rounds
- Round 1 (independent): **9.0/10 — ship gate passed.** Notes (session reset not observable in tests, no reset after caller cancellation, duplicate timeout test) → PARLEY-15.

## Score

| # | Criterion | Score |
| --- | --- | --- |
| 1 | Requirements fit | 1 |
| 2 | Test depth | 0.5 |
| 3 | Reliability | 0.5 |
| 4 | Security | 1 |
| 5 | Maintainability | 1 |
| 6 | UX | 1 |
| 7 | Accessibility | 1 |
| 8 | Performance | 1 |
| 9 | Docs | 1 |
| 10 | Delivery | 1 |
| | **Total** | **9.0 / 10** (round 1) |
