# 001 Learning suite — plan

Skeleton first (the app already runs; PARLEY-1 makes it testable), then one vertical feature per item.

| Slice | Items | Release boundary |
| --- | --- | --- |
| 1 Habit + listening | PARLEY-1 baseline, PARLEY-2 progress & streak, PARLEY-3 listening (dictation + shadowing) | v0.2.0 (local only, tag + push) |
| 2 Speak + write with on-device AI | PARLEY-4 conversation role-play, PARLEY-5 writing coach | v0.3.0 |
| 3 Read + data | PARLEY-6 graded reading, PARLEY-7 CSV import/export, PARLEY-8 reminder | v0.4.0 |

Coverage: S1→PARLEY-1, S2→PARLEY-2, S3→PARLEY-3, S4→PARLEY-4, S5→PARLEY-5, S6→PARLEY-6, S7→PARLEY-7, S8→PARLEY-8.
Benchmark harness: `make bench` (progress aggregation) lands with PARLEY-2; AI latency with PARLEY-4.
Circuit breaker: if a slice overruns, cut in this order — PARLEY-8, shadowing speed control, reading AI generation (keep bundled passages).
