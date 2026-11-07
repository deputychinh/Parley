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

## Score
Pending review.
