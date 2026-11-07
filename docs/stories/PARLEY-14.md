# PARLEY-14 — Debt from PARLEY-4 (round 3)

## Changes
- `Coach.isPraise`: "good job", "well done", "great work", "you did"… never become a "more natural" phrase to save
  (`naturalPhrasingOnlyWhenNew` includes the reviewer's real example).
- `ModelCoach.turn` is cancelled after 30 s with a Vietnamese error, so "Đang nghĩ…" can't hang.
- The interpreter status ("Sẵn sàng") is not shown as the window subtitle on the chat; listen buttons are callout-sized
  with vertical padding (≥ 24 pt).
- `conversation.png` / `conversation-chat.png` regenerated (green correction palette, no interpreter toolbar).

## Follow-ups noted from the PARLEY-5 review (cosmetic, not fixed here)
Diff changes without a mistake card are not explained; changing the level resets a free topic; the writing legend says
"đã sửa (bạn viết)" for red while red marks the fix.

## Review rounds
- Round 1 (independent): 7.5/10 — timeout untested (hand-written duplicate), praise list caught real rewrites. Fixed in d2f2f23 (`mainActorTimeout` + test, phrase-only praise list).
- Round 2 (fresh): 8.0/10 — timeout not tested inside `turn`; caller cancellation reported as a timeout; session possibly busy after a timeout; "I did a good job…" treated as praise.
  Fixed: `ModelCoach(responder:timeout:)` injectable (`ModelCoachTimeoutTests.turnTimesOutWithItsOwnError`, `fastResponderPassesThrough`); `TimeoutError` vs `CancellationError` (`callerCancellationIsNotATimeout`); the session is recreated after a timeout; first-person sentences are never praise.

- Round 3 (fresh, last allowed): 8.0/10 — requirements fit 0.5: the timeout still waited for work that ignores cancellation (both helpers). **Blocked** under the round-3 rule → continued as PARLEY-17.

## Score
Blocked after round 3 (requirements fit 0.5); continued in PARLEY-17.
