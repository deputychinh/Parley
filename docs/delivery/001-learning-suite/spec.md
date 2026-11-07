# 001 Learning suite — spec

Brief: [brief.md](brief.md). UI copy: Vietnamese. Everything runs offline (on-device frameworks only).

## Stories and acceptance criteria

### S1 · Engineering baseline (PARLEY-1)
- **AC1.1** `make ci` builds with the full Xcode toolchain and runs all unit tests; it fails on any failing test.
- **AC1.2** Tests and screenshots never touch the user's real data: `PARLEY_DATA_DIR` redirects every store.
- **AC1.3** `make shot ROUTE=<route>` captures the main window to `docs/screenshots/` using a seeded sample data folder.

### S2 · Progress and streak (PARLEY-2)
As a learner I want to see what I studied each day so that I keep the habit.
- **AC2.1** Every graded answer (practice, grammar, listening; later speaking, writing, reading) adds XP to today's log, per skill.
- **AC2.2** Streak = consecutive days that reached the daily XP goal, ending today or yesterday; a missed day resets it to 0.
- **AC2.3** *Tiến độ* shows streak, today's XP vs goal (ring), 12-week heatmap, totals per skill, words known; goal adjustable (10–200 XP).
- **AC2.4** Empty state when nothing was studied yet; an unreadable log file is moved aside, never overwritten.
- **AC2.5** Sidebar shows the streak and today's progress.

### S3 · Listening practice on real audio (PARLEY-3)
As a learner I want to drill the sentences I actually heard so that I understand real speakers.
- **AC3.1** *Luyện nghe* lists sentences from saved sessions that have a recording and a time offset; fallback source: curated example sentences read by TTS.
- **AC3.2** A clip plays from its offset to the next line's offset on the same recording (max 15 s); replay and 0.75×/1× speed.
- **AC3.3** Dictation: user types what they heard; result shows a word-by-word diff (correct / wrong / missing) and a % score.
- **AC3.4** Shadowing: user repeats via the microphone; recognized words are scored against the sentence (≥ 80 % = pass).
- **AC3.5** Missing recording, microphone errors and empty history each show a clear state, no crash.

### S4 · AI conversation role-play (PARLEY-4)
- **AC4.1** Pick a scenario (≥ 8: standup, job interview, restaurant, hotel, small talk, deadline negotiation, customer support, doctor) and level.
- **AC4.2** AI opens and speaks its line (TTS); user answers by voice or text; AI replies in role.
- **AC4.3** Each user turn gets feedback: corrected sentence (or "OK"), a more natural phrasing, a short Vietnamese explanation.
- **AC4.4** A phrase from feedback can be saved to vocabulary; the session ends with a summary (turns, corrections).
- **AC4.5** Without Apple Intelligence the screen explains why and how to enable it; no network call is ever made.

### S5 · Writing coach (PARLEY-5)
- **AC5.1** Prompts by level (A2–C1, workplace + daily life) or free topic; word counter.
- **AC5.2** Feedback: corrected text with changes highlighted, a list of mistakes (original → fix, Vietnamese explanation), an estimated CEFR band.
- **AC5.3** Drafts and feedback are saved and listed; same fallback as AC4.5.

### S6 · Graded reading (PARLEY-6)
- **AC6.1** Graded passages for each level work without the model. *(Cut for v0.2.0: generating new passages with the on-device model — see PARLEY-19.)*
- **AC6.2** Select a word → the same lookup card as the transcript (meaning, IPA, listen, add to vocabulary).
- **AC6.3** 3 comprehension questions with feedback; read aloud with TTS.

### S7 · Vocabulary import/export (PARLEY-7)
- **AC7.1** Export vocabulary as CSV (term, meaning, IPA, example, example translation, mastered).
- **AC7.2** Import CSV/TSV; duplicates skipped; malformed rows reported with line numbers; nothing lost on a bad file.

### S8 · Daily reminder (PARLEY-8)
- **AC8.1** Optional local notification at a chosen time when today's XP goal is not met yet.

## Non-goals
Cloud AI or accounts, iOS/Android apps, phoneme-level acoustic scoring (no offline model available), leaderboards.

## Quality targets (workloads in `benchmarks/plan.md`)
- Progress aggregation over 3 years of daily logs: < 20 ms.
- Clip start after pressing play: < 300 ms (local file seek).
- AI feedback turn: < 8 s p50 on M-series (`HYPOTHESIS`, measured in slice 2).
