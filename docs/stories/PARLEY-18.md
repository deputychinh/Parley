# PARLEY-18 — Reading for v0.2.0 (continues blocked PARLEY-6)

Circuit breaker from plan.md applied: "cut … reading AI generation (keep bundled passages)". The appetite (3 slices)
is spent and the on-device model could not show a usable passage in review (0 of 4 real runs).

## Changes
- `ReadingStore.generatorEnabled = false`: the "Tạo bài đọc mới bằng AI" card is hidden. `PassageWriter`,
  `ModelPassageWriter`, `ReadingRules.supported` and their tests stay, so PARLEY-19 can turn it back on with
  evidence from `make ai-eval`.
- spec AC6.1 now reads "graded passages for each level work without the model" (the cut is noted there).
- Reading XP at most once per passage per day: `ReadingData.xpDay` (persisted) + per-visit tracking; leaving and
  reopening, or restarting the app, earns nothing more that day; another passage or the next day counts.

## Evidence
| Finding | Evidence |
| --- | --- |
| XP once per passage per day | `ReadingXPPerDayTests.reopeningAPassageTheSameDayEarnsNothing` (incl. restart), `tomorrowCountsAgain` |
| generator off | `generatorIsOffForThisRelease`; `ReadingView` shows the card only when enabled |
| bundled reading still complete | `bundledPassagesAreUsable`, `bundledExplanationsAreVietnamese`, `ReadingQuizTests` |
Screenshots: the display was locked in this cycle ("could not create image from window"); `reading.png` /
`reading-passage.png` must be retaken before the demo.

## Score
Pending review.
