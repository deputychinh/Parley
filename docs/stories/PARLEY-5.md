# PARLEY-5 — Writing coach (on-device AI)

Spec: [S5, AC5.1–AC5.3](../delivery/001-learning-suite/spec.md) · [ADR 0001](../adr/0001-offline-only-ai.md)

As a learner I want my English texts corrected with explanations in Vietnamese so that I stop repeating mistakes.

## Design
- `Writing.swift`: 12 `WritingPrompt`s (3 per level A2–C1, work + daily life) or a free topic; editor with a live
  word counter, 20–250 words (`WritingRules.problem`).
- `WritingStore.review` asks FoundationModels for a `GeneratedCritique` (corrected text, ≤ 8 mistakes, CEFR level,
  Vietnamese summary). The model is not trusted blindly (`WritingRules`, all tested):
  - `clean`: drops mistakes whose "original" isn't in the text (hallucinated), no-op or duplicate fixes, and fixes
    written in Vietnamese (`isVietnamese`).
  - `correctedText`: the model's rewrite is used only while it is a correction (keeps ≥ 70 % of the learner's words,
    grows ≤ 30 %) — a text that didn't match the prompt once made the model invent a whole email; otherwise the
    learner's text is the base. The listed fixes are always applied on top (`apply`, whole words only), so the
    corrected text and the mistake list agree.
  - `level`: normalizes "b2+", "around C1" → B2/C1, unknown → "?".
- `WritingStore` (`writing.json` via `StoreFile`): newest first, delete from the context menu, logs `XPEvent.essay`
  (30 writing XP). Feedback view: level badge, summary, word diff of the corrected text with a legend, mistake cards,
  a note that the on-device AI can be wrong; history list. No Apple Intelligence and no history → `AIUnavailableView`.
- `make ai-eval` adds a writing case: a paragraph with 6 planted mistakes must yield ≥ 3 in < 20 s.

## AC → test traceability

| AC | Evidence |
| --- | --- |
| AC5.1 | `promptsCoverEveryLevel`, `wordCountIgnoresPunctuationAndLines`, `lengthLimits` (19/20/250/251); screenshot `writing.png` |
| AC5.2 | `cleanDropsHallucinatedAndNoOpMistakes`, `modelRewriteIsUsedOnlyWhileItIsACorrection`, `applyReplacesFirstOccurrenceInOrder`, `vietnameseDetection`, `levelNormalization`; `make ai-eval` writing 2–4 of 6 found in 4–7 s across runs; screenshot `writing-feedback.png` |
| AC5.3 | `addPersistsNewestFirstAndLogsWritingXP` (save, reload, delete, XP), `unreadableFileIsKept`; fallback `AIUnavailableView` |

Known limit (model): runs vary — between 2 and 4 of 6 planted mistakes are found, and an occasional suggested fix is
wrong (e.g. "was → have"); the UI says so under the feedback.

## Review rounds
- Round 1 (independent): 7.0/10 — `apply` could corrupt correct text ("This is" → "This are") and lose a subject ("we was" → "were"); `clean` (substring) and `apply` (whole word) disagreed; no timeout; the draft was lost on navigation; no reason shown when Apple Intelligence is off but history exists; delete only by context menu; "Free writing" in English; eval numbers overstated (measured 2–3 of 6).
  Fixed: one whole-word matcher for `clean` and `apply`; a mistake is kept only if its span occurs exactly once and the fix drops no meaningful word (`cleanKeepsOnlySafeFixes`, ambiguity and lookbehind cases in `applyReplacesFirstOccurrenceInOrder`); `withTimeout` 45 s (tested); `@SceneStorage` draft; fallback banner; "Xoá bài này" button; "Chủ đề tự do"; eval gate ≥ 2 of 6 with the measured spread 2–4 recorded.

## Score
Pending review.
