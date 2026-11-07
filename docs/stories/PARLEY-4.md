# PARLEY-4 — AI conversation role-play (on-device)

Spec: [S4, AC4.1–AC4.5](../delivery/001-learning-suite/spec.md) · Design: [design.md](../delivery/001-learning-suite/design.md) · [ADR 0001](../adr/0001-offline-only-ai.md)

As a learner I want to practise real situations with a partner that corrects me, without sending my words anywhere.

## Design
- `Conversation.swift`: 10 `Scenario`s (standup, interview, deadline, code review, small talk, support, restaurant,
  hotel, airport, doctor) × CEFR level A2–C1. One `LanguageModelSession` per conversation (keeps context), structured
  `CoachTurn` (`reply`, `corrected`, `natural`, `tipVi`) via `@Generable`.
- Deterministic guards in `Coach` (tested): input trimmed and capped at 400 chars; a correction is shown only when the
  words really differ (case/punctuation/apostrophes ignored); "more natural" only when it adds something.
- `ConversationModel.send`: on success logs `XPEvent.turn` (voice → speaking, typed → writing); on any model error the
  learner's message is removed and restored to the text field with a Vietnamese error (context-window case named).
- UI: scenario picker with level; chat with AI bubbles (listen button, optional auto-read), learner bubbles (mic/keyboard
  icon), feedback card (word diff of the correction, natural phrasing with listen + "Lưu cụm từ" → vocabulary, tip);
  composer with mic (MicCheck) and text; summary (turns, corrections, saved phrases, the corrected sentences).
- No Apple Intelligence → `AIUnavailableView` with a button to the settings pane; no network code (offline guard).
- `make ai-eval`: 8 eval cases (6 planted mistakes, 2 correct sentences) → hit rate + p50 latency.

## AC → test traceability

| AC | Evidence |
| --- | --- |
| AC4.1 | `CoachTests.scenarioCatalog` (≥ 8, required ids, valid SF Symbols), `instructionsCarryRoleAndLevel`; screenshot `conversation.png` |
| AC4.2 | screenshot `conversation-chat.png` (AI opener, learner turn, AI reply in role); TTS via `Speaker`; mic via `MicCheck` (manual) |
| AC4.3 | `correctionOnlyWhenWordsDiffer` (6 cases), `naturalPhrasingOnlyWhenNew`; `make ai-eval` 6/8 (75 %), p50 2.2 s; screenshot shows diff + Vietnamese tip |
| AC4.4 | "Lưu cụm từ" → `VocabStore.add`; summary view (turns, corrections, saved) |
| AC4.5 | `AIUnavailableView` when `ExampleWriter.available` is false; `make offline-guard` |
| XP | `XPWiringTests.eventRules` (`.turn`) |

Known limit (model): the eval missed present-perfect-with-past-time and present-perfect-continuous errors (2/8). The
tip prompt carries an example to keep explanations on the grammar rule.

## Score
Pending review.
