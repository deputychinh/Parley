# Performance plan

| ID | Workload | Data | Metric | Target | Harness | Baseline (2026-11-08, M-series) |
| --- | --- | --- | --- | --- | --- | --- |
| W1 | Progress aggregation (streak + 12-week heatmap + skill totals ×2) | 3 years of daily logs, 6 skills/day | wall time, single run | < 20 ms | `make bench` → `BenchProgress` | 3.4 ms |
| W2 | Listening clip start | seeded 25 s .m4a, seek to the last clip | open + prepare + seek | < 300 ms | `make bench` → `BenchSeededClipTests` | 15–93 ms (best of 3, machine load varies) |
| W4 | Furigana for the longest text that gets readings | `Furigana.limit` (1 000) Japanese characters, 600 pt wide | segmenting / main-actor layout + render, best of 3 | < 100 ms / < 400 ms | `make test` → `BenchFurigana.segmentsAtTheLimit`; `make bench` → `layoutAtTheLimit` | 3 ms / 178 ms (2026-11-10) |
| W5 | Screenshot OCR + translation (PARLEY-21) | rendered 6-line Japanese screenshot (≤ 300 chars), packs installed | wall time, 5 warm runs | p50 ≤ 3 s | `Parley --translate-image <png>` (prints the time); not in CI — needs the language packs | p50 1.88 s (cold first run 16.6 s: models load) |
| W3 | On-device AI turn | conversation / writing feedback | p50 latency | < 8 s (`HYPOTHESIS`) | `make ai-eval` | — (PARLEY-4) |

CI guard: `BenchProgress` runs inside `make test`, so a regression past the target fails `make ci`.
