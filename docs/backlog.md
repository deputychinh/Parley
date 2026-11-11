# Backlog

Status: todo · doing · done · debt · blocked. Prefix `PARLEY`. Delivery: [001-learning-suite](delivery/001-learning-suite/plan.md), [002-japanese-translate](delivery/002-japanese-translate/plan.md).

| ID | Release | Item | Size | Status |
| --- | --- | --- | --- | --- |
| PARLEY-1 | v0.2.0 | Engineering baseline: Swift Testing target, `make ci`, `PARLEY_DATA_DIR`, screenshot script, offline guard | M | done |
| PARLEY-2 | v0.2.0 | Progress & streak: activity log (XP per skill/day), *Tiến độ* screen, heatmap, goal, sidebar streak | M | done (8.0) |
| PARLEY-3 | v0.2.0 | Listening on real meeting audio: dictation with word diff, shadowing with mic scoring, speed | L | done (7.5) |
| PARLEY-4 | v0.3.0 | AI conversation role-play (on-device) with per-turn corrections | L | done (7.5) |
| PARLEY-5 | v0.3.0 | Writing coach (on-device AI) with explained mistakes and history | M | done (9.0) |
| PARLEY-6 | v0.4.0 | Graded reading: bundled + AI passages, lookup, questions | M | blocked → PARLEY-18 |
| PARLEY-7 | v0.4.0 | Vocabulary CSV import/export | S | done (8.0) |
| PARLEY-8 | v0.4.0 | Daily study reminder notification | S | done (8.5) |
| PARLEY-9 | v0.2.0 | Debt from PARLEY-1 review: shot.sh stops only its own PID (trap on exit, window by PID); tests for StudyStore/PronunciationStore move-aside and the `--data-dir` hookup; one source for the default folder; Settings shows `Model.dataDir`; honest name for the seed-write test | S | blocked → PARLEY-10 |
| PARLEY-10 | v0.2.0 | Continue PARLEY-9: one `--data-dir` parser refusing `=`/empty/flag values (exit 2), shot-test ignoring `ParleyTests` helpers | S | done (9.5) |
| PARLEY-11 | v0.2.0 | Debt from PARLEY-2: lowering the goal meets today (test), progress banner, refreshed narrow screenshot, status.md | S | done (9.5) |
| PARLEY-12 | v0.2.0 | Debt from PARLEY-3: mic-stop race, clip end within the file, secondary skip button, recognition errors shown, W2 row | S | done (8.5) |
| PARLEY-13 | v0.2.0 | Sandboxed runs (`--data-dir`) use their own defaults domain and never schedule reminders | S | blocked → PARLEY-16 |
| PARLEY-14 | v0.2.0 | Debt from PARLEY-4: praise not offered as a phrase, model timeout, chat subtitle, button size, screenshots | S | blocked → PARLEY-17 |
| PARLEY-15 | v0.3.0 | Debt from PARLEY-7/8/12 final rounds: headerless `;` CSV tie and BOM before `#separator`, import off the main actor; reminder footer reset + time-zone change + goal-met wiring test; MicCheck `failure` reset, skip-while-listening race, failed-start cleanup test; launch-path refusal test, `defaults-guard` bypasses, cfprefsd empty plist; ModelCoach session reset observable + after caller cancel; reading visit-start seam and generator condition tests; retake reading/conversation screenshots | M | todo |
| PARLEY-16 | v0.2.0 | Continue PARLEY-13: real app refuses sandboxed runs, clean only finished runs' domains (files deleted), SIGTERM cleanup, stricter guard | S | done (9.0) |
| PARLEY-17 | v0.2.0 | Continue PARLEY-14: one `modelTimeout` that returns on time even if the model ignores cancellation; session reset | S | done (9.0) |
| PARLEY-18 | v0.2.0 | Continue PARLEY-6: AI generation cut for v0.2.0 (circuit breaker), reading XP once per passage per day | S | done (9.0) |
| PARLEY-19 | v0.3.0 | AI-written reading passages back on, with a reading case in `make ai-eval` (success rate, time), a cancel button, no retry when cancelled, UUID ids, reject questions whose wrong options are also in the text | M | todo |
| PARLEY-20 | v0.3.0 | Live interpreter hears Japanese: echo merge for languages without spaces, pronunciation only for English sources, `--source/--target` on `--file`, Japanese `make pipeline` | S | done (9.0) |
| PARLEY-21 | v0.3.0 | "Dịch văn bản & ảnh": type/paste text, open/drop/paste image, region capture → on-device OCR → translation to EN/VI | M | done (9.5) |
| PARLEY-22 | v0.3.0 | Kana readings (furigana) for Japanese source text on the translate screen | S | done (9.5) |
| PARLEY-23 | v0.3.0 | Debt from PARLEY-20: `isEcho` tokenizes once per sentence (≈0.5 ms/call for Japanese on the main actor), self-test for `check-sdk.sh`/`link-flags.sh` (message when link-flags fails under build.sh), one `CLIArgs` type and one Xcode-path default | S | todo |
| PARLEY-24 | v0.3.0 | Debt from PARLEY-21: "chưa dịch" note for paragraphs left after a cancelled translation, keyboard-only pass recorded, test for the remembered target, pixel limit before OCR, CLI reports truncation, Finder copy of a non-image file, picker row alignment at ~640 pt, Vietnamese language names | S | todo |
| PARLEY-25 | v0.3.0 | Debt from PARLEY-22: result-card header crowded at ~760 pt (icon-only buttons there), readings overhang neighbouring kana instead of widening the base text, a test for the digit-inside-token rule | S | todo |
| PARLEY-26 | v0.3.1 | Translate on paste and typing ("Tự dịch", 0.6 s after the text settles), no retry of the same request | S | done (9.5) |
| PARLEY-27 | v0.3.1 | Bug: the Mini window could not scroll back down to the last line after scrolling up, and kept only 40 lines | S | done |
| PARLEY-28 | v0.3.1 | Debt from PARLEY-26: screenshots of the empty state with "Tự dịch" on/off and a finished narrow shot, a manual pass with the Japanese input method, a test for the Mini note above 200 lines | S | done (IME pass left to the owner) |
| PARLEY-29 | v0.3.1 | "Mỗi ngày": decide all words left at once ("Đã biết hết" with a confirmation, "Học hết" for words whose meaning is ready) | XS | done |
| PARLEY-30 | v0.3.1 | "Học tập": ↩ for the main action (flip, "Đã nhớ", "Tiếp" after typed answers; grammar lesson start and result). Other screens checked: they already have ↩ or have no step-by-step flow | XS | done |
