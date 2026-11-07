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
- Round 2 (fresh): 8.0/10 — sandbox guard untested; reminders only rebuilt at launch/settings/goal. Fixed in d2f2f23 (activation + day-change observers, `sandboxedRunsNeverTouchNotifications`).
- Round 3 (fresh, last allowed): 8.5/10 — shipped under the round-3 rule. Remaining (denied footer not reset when toggled off, time-zone change, goal-met wiring test) → PARLEY-15.

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
| 10 | Delivery | 0.5 |
| | **Total** | **8.5 / 10** (round 3 cap; debt PARLEY-15) |
