# PARLEY-6 — Graded reading

Spec: [S6, AC6.1–AC6.3](../delivery/001-learning-suite/spec.md) · [ADR 0001](../adr/0001-offline-only-ai.md)

As a learner I want short texts at my level with questions, and to look up any word I don't know without leaving the text.

## Design
- `Resources/readings.json`: 8 bundled passages (2 each A2, B1, B2, C1; 138–222 words, work and daily life), 3 questions
  each with a Vietnamese explanation. They work without Apple Intelligence.
- `Reading.swift`: `ReadingRules` (tested) — `validQuestions` (prompt, exactly 4 distinct options, answer among them,
  normalized to the option's spelling), `problem(with:)` (title, 80–400 words, ≥ 2 valid questions), `paragraphs`,
  `score`. AI passages: `ReadingStore.generate(topic:level:)` with `@Generable` output, a 60 s timeout, and the same
  rules — an unusable result is a Vietnamese error, never a broken quiz.
- `ReadingStore` (`reading.json` via `StoreFile`): generated passages (delete from the context menu), best score per
  passage, `XPEvent.reading` per answered question (reading skill).
- UI: level filter, passage cards (level, topic, word count, best score, ✨ for AI), generator card (or the reason it is
  unavailable). Passage view: the text in `TranscriptView` (`showMeta: false`, no auto-scroll) so selecting a word opens
  the same `WordCard` as the interpreter (meaning, IPA, listen, add to vocabulary); "Nghe cả bài" (TTS); quiz with
  feedback and explanation, retry.

## AC → test traceability

| AC | Evidence |
| --- | --- |
| AC6.1 | `bundledPassagesAreUsable` (≥ 8, every level, every passage and question valid), `invalidQuestionsAreDropped`, `passageProblems`; screenshot `reading.png`; AI generation checked by hand (same rules) |
| AC6.2 | screenshot `reading-passage.png` (selecting "connection pool" opens WordCard with IPA, meaning, context and "Thêm vào từ vựng") |
| AC6.3 | `scoreCountsCorrectAnswers`, `answersLogReadingXPAndBestScoreIsKept`, `generatedPassagesPersistAndCanBeRemoved`, `readingXPEvent`; "Nghe cả bài" via `Speaker` |

## Review rounds
- Round 1 (independent): 8.0/10 — retry farmed XP, read-aloud button stuck, 2 questions accepted, toolbar on reading, answer often the longest option, English explanations from the model. Fixed in d2f2f23 (`ReadingQuiz`, `Speaker.isSpeaking`, exactly 3 questions, `Route.showsInterpreter`, `displayOrder`, `vietnameseOrEmpty`, US spelling).
- Round 2 (fresh): 6.5/10 — generated quizzes asked about things the text never said; 9 bundled explanations were English quotes; retry after a timeout doubled the wait; generation kept running after leaving; generation untestable; dead `answer(correct:)`.
  Fixed: `PassageWriter` protocol (`ModelPassageWriter` = the model) with `ReadingGenerationTests` (good draft, unsupported answer → retry once → error, no retry after `TimeoutError`, English explanations dropped); `ReadingRules.supported` (answers come from the text) for generated passages; all bundled explanations Vietnamese (`bundledExplanationsAreVietnamese`); generation cancelled when the screen goes; `@Guide` length follows the request; wrong picked option has a VoiceOver label; dead code removed. Screenshots could not be refreshed this round (display locked: "could not create image from window").
- Round 3 (fresh, last allowed): 7.0/10 — requirements fit 0.5: generation proven only with a fake writer; the real model went 0 for 4 (all timed out at ~60 s, machine load ~88); stale screenshots; XP re-earnable by reopening a passage. **Blocked** under the round-3 rule → continued as PARLEY-18 (scope cut: generation off for v0.2.0, PARLEY-19 in the backlog).

## Score
Blocked after round 3 (requirements fit 0.5); continued in PARLEY-18.
