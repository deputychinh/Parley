# Performance plan

| ID | Workload | Data | Metric | Target | Harness | Baseline (2026-11-08, M-series) |
| --- | --- | --- | --- | --- | --- | --- |
| W1 | Progress aggregation (streak + 12-week heatmap + skill totals ×2) | 3 years of daily logs, 6 skills/day | wall time, single run | < 20 ms | `make bench` → `BenchProgress` | 3.4 ms |
| W2 | Listening clip start | local .m4a seek | time to first audio | < 300 ms | manual (AVAudioPlayer prepare + seek) | — (PARLEY-3) |
| W3 | On-device AI turn | conversation / writing feedback | p50 latency | < 8 s (`HYPOTHESIS`) | `make ai-eval` | — (PARLEY-4) |

CI guard: `BenchProgress` runs inside `make test`, so a regression past the target fails `make ci`.
