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
| AC2.1 | `XPWiringTests` (event → skill/XP table; VocabStore, StudyStore, PronunciationStore log XP), `ActivityStoreTests.addsXPPerSkillAndDayAndPersists`; listening/conversation in PARLEY-3/4 |
| AC2.2 | `ActivityStoreTests.streak` (5 cases: running, today open, gap, broken, empty), `goalIsClampedAndMetDaysAreKept`, `SeedActivityTests` |
| AC2.3 | `heatmapIsTwelveMondayFirstWeeksEndingThisWeek`, `totalsPerSkillWithOptionalWindow`, goal clamp test; screenshot `docs/screenshots/progress.png` |
| AC2.4 | `StoreFileTests` (second corrupt file, unmovable file, save error), `unreadableFileIsMovedAsideNotOverwritten`; screenshot `progress-empty.png` |
| AC2.5 | sidebar row `Tiến độ` with `MiniRing` + badge (screenshot) |
| Perf W1 | `BenchProgress.threeYearsAggregateUnder20ms` → 3.4 ms (target < 20 ms) |

## Review rounds
- Round 1 (independent): 5.0/10 — data loss when an `.unreadable.json` already existed (shared by all stores), save errors swallowed, XP call sites untested (deleting them kept tests green), `met` reload untested, design.md stale, heatmap bars / 84 VoiceOver cells, empty skill rows, ring "not met" after raising the goal, branch unpushed.
  Fixed: `StoreFile` (unique aside name, read-only when the move fails, `problem` shown) for all four stores; `XPEvent` mapping + stores log XP themselves (`XPWiringTests` per store); `metSurvivesARestart`; square 16 px heatmap cells with one VoiceOver summary; zero-XP skills hidden; ring uses `metToday`; design.md updated; branch pushed.

## Score
Pending review.
