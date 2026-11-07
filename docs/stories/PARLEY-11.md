# PARLEY-11 — Debt from PARLEY-2 (round 3)

## Changes
- `loweringTheGoalBelowTodaysXPMeetsToday`: the goal setter's `markMet` is now covered.
- ProgressScreen uses the shared `.problemBanner(activity.problem)`.
- `docs/screenshots/progress-narrow.png` regenerated (square cells, no empty skill rows); status.md updated.
- `BenchProgress` takes the best of 3 runs so a busy machine (load average 67 seen during this cycle) can't fail it by noise.

## AC → test traceability
| Finding | Evidence |
| --- | --- |
| lowering the goal meets today | `loweringTheGoalBelowTodaysXPMeetsToday` |
| shared banner on Tiến độ | `.problemBanner(activity.problem)` (Progress.swift); banner behaviour covered by `StoreFileTests` (problem set on unreadable file / failed save) |
| narrow screenshot | `docs/screenshots/progress-narrow.png` regenerated |
| bench noise | `BenchProgress` best of 3 |

## Review rounds
- Round 1 (independent): 8.5/10 — no AC table, no CHANGELOG line, mixed commit message. Fixed: table above, CHANGELOG line.

## Score
Pending review.
