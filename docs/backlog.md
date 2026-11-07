# Backlog

Status: todo · doing · done · debt · blocked. Prefix `PARLEY`. Delivery: [001-learning-suite](delivery/001-learning-suite/plan.md).

| ID | Release | Item | Size | Status |
| --- | --- | --- | --- | --- |
| PARLEY-1 | v0.2.0 | Engineering baseline: Swift Testing target, `make ci`, `PARLEY_DATA_DIR`, screenshot script, offline guard | M | done |
| PARLEY-2 | v0.2.0 | Progress & streak: activity log (XP per skill/day), *Tiến độ* screen, heatmap, goal, sidebar streak | M | done (8.0) |
| PARLEY-3 | v0.2.0 | Listening on real meeting audio: dictation with word diff, shadowing with mic scoring, speed | L | done (7.5) |
| PARLEY-4 | v0.3.0 | AI conversation role-play (on-device) with per-turn corrections | L | done (7.5) |
| PARLEY-5 | v0.3.0 | Writing coach (on-device AI) with explained mistakes and history | M | done (9.0) |
| PARLEY-6 | v0.4.0 | Graded reading: bundled + AI passages, lookup, questions | M | doing |
| PARLEY-7 | v0.4.0 | Vocabulary CSV import/export | S | done (8.0) |
| PARLEY-8 | v0.4.0 | Daily study reminder notification | S | done (8.5) |
| PARLEY-9 | v0.2.0 | Debt from PARLEY-1 review: shot.sh stops only its own PID (trap on exit, window by PID); tests for StudyStore/PronunciationStore move-aside and the `--data-dir` hookup; one source for the default folder; Settings shows `Model.dataDir`; honest name for the seed-write test | S | blocked → PARLEY-10 |
| PARLEY-10 | v0.2.0 | Continue PARLEY-9: one `--data-dir` parser refusing `=`/empty/flag values (exit 2), shot-test ignoring `ParleyTests` helpers | S | done (9.5) |
| PARLEY-11 | v0.2.0 | Debt from PARLEY-2: lowering the goal meets today (test), progress banner, refreshed narrow screenshot, status.md | S | done (9.5) |
| PARLEY-12 | v0.2.0 | Debt from PARLEY-3: mic-stop race, clip end within the file, secondary skip button, recognition errors shown, W2 row | S | done (8.5) |
| PARLEY-13 | v0.2.0 | Sandboxed runs (`--data-dir`) use their own defaults domain and never schedule reminders | S | doing |
| PARLEY-14 | v0.2.0 | Debt from PARLEY-4: praise not offered as a phrase, model timeout, chat subtitle, button size, screenshots | S | doing |
| PARLEY-15 | v0.3.0 | Debt from PARLEY-7/8/12 final rounds: headerless `;` CSV tie and BOM before `#separator`, import off the main actor; reminder footer reset + time-zone change + goal-met wiring test; MicCheck `failure` reset, skip-while-listening race, failed-start cleanup test | M | todo |
