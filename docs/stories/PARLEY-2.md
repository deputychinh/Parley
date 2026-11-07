# PARLEY-2 — Progress & streak

Spec: [S2, AC2.1–AC2.5](../delivery/001-learning-suite/spec.md) · Design: [design.md](../delivery/001-learning-suite/design.md)

As a learner I want to see how much I studied each day, per skill, so that I keep the habit.

## Design
- `Progress.swift`: `Skill` (vocabulary, grammar, listening, speaking, writing, reading), `XP` rules (10 right, 2 wrong
  attempt, 5 per new daily word), `ActivityStore` → `activity.json`
  (`{ "days": { "yyyy-MM-dd": { skill: xp } }, "goal": 50, "met": ["yyyy-MM-dd"] }`).
- Streak counts days in `met` (recorded when the day reached the goal *at that time*), so changing the goal never
  rewrites history. Ends today, or yesterday while today is still open.
- Pure, tested aggregation: `streak`, `heatmap` (12 Monday-first weeks), `totals(since:)`. `StudyStore.day` now reuses
  one `en_US_POSIX` formatter (it ran once per heatmap cell / streak step).
- Injected once with `.environment(ActivityStore)`; XP events in `PracticeSession.record` (speak cards → speaking),
  `GrammarQuiz.choose`, `PronunciationView.finish`, `DailyView` ("Học từ này"). Listening/writing/reading join in later items.
- UI: *Tiến độ* screen (today ring + goal stepper 10–200, streak tile, words known, heatmap with tooltips, skill bars
  7 days + all-time), empty state; sidebar row with a mini ring and 🔥 streak badge. Header stacks in a narrow window.
- Debug: `--window-size W,H` and `SHOT_SIZE=W,H scripts/shot.sh …` for narrow-layout screenshots.

## AC → test traceability

| AC | Evidence |
| --- | --- |
| AC2.1 | `ActivityStoreTests.addsXPPerSkillAndDayAndPersists`, `xpRules`; call sites listed above (`grep -n "activity.add" Sources`) |
| AC2.2 | `ActivityStoreTests.streak` (5 cases: running, today open, gap, broken, empty), `goalIsClampedAndMetDaysAreKept`, `SeedActivityTests` |
| AC2.3 | `heatmapIsTwelveMondayFirstWeeksEndingThisWeek`, `totalsPerSkillWithOptionalWindow`, goal clamp test; screenshot `docs/screenshots/progress.png` |
| AC2.4 | `unreadableFileIsMovedAsideNotOverwritten`; empty state in `ProgressScreen` (no days) |
| AC2.5 | sidebar row `Tiến độ` with `MiniRing` + badge (screenshot) |
| Perf W1 | `BenchProgress.threeYearsAggregateUnder20ms` → 3.4 ms (target < 20 ms) |

## Score
Pending review.
