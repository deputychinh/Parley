# PARLEY-8 — Daily study reminder

Spec: [S8, AC8.1](../delivery/001-learning-suite/spec.md)

As a learner I want a nudge at a time I choose, only on days I haven't studied enough, so that the streak survives busy days.

## Design
- `Reminder.swift`: local notifications only (UserNotifications). `fireDates(now:minutes:metToday:days:)` (pure, tested):
  the chosen time on each of the next 7 days, skipping today once the time has passed or the goal is met.
  `reschedule()` removes Parley's pending reminders (`parley.reminder.<day>`) and adds the new set; today's text
  names the XP still missing (`body(remaining:)`).
- Rescheduled at launch, when settings change, and once when today first reaches the goal
  (`ActivityStore.onGoalMet`), so a met day never nags and a few days away from the app still get reminders.
- Settings → "Nhắc học": toggle + time (default 20:00, `reminderOn` / `reminderMinutes` in UserDefaults); permission
  asked when turned on; a footer says when macOS blocks notifications. Debug `--settings` opens Settings alone.

## AC → test traceability

| AC | Evidence |
| --- | --- |
| AC8.1 | `ReminderTests` (today before the time, skip when met / time passed incl. the exact minute, clamping, 7 days, body text), `GoalMetCallbackTests` (fires once); screenshot `settings.png`; delivery checked by hand (needs the signed app and notification permission) |

## Review rounds
- Round 1 (independent): 7.5/10 — screenshot/`--data-dir` instances rebuilt the owner's real reminders from sample data (shared defaults domain); quick off/on could leave stale reminders; permission denial not re-checked when Settings reopens; `requestAuthorization` errors hidden.
  Fixed: sandboxed runs never schedule or ask (PARLEY-13: own defaults domain, `Reminder.reschedule` returns early); rebuilds are serialized (each waits for the previous); `isDenied()` checked whenever Settings appears; permission errors logged. Known limit kept: today's "còn X XP" text is fixed when scheduled (rebuilt when the goal is met).

## Score
Pending review.
