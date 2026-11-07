# 001 Learning suite — design

## Driving characteristics → decisions → fitness checks

| Characteristic | Decision | Fitness check |
| --- | --- | --- |
| Privacy / offline (product promise) | Only on-device frameworks: Speech, Translation, AVFoundation, FoundationModels, NaturalLanguage. No URLSession anywhere in `Sources/`. | `make ci` greps `Sources/` for `URLSession` and fails on a hit. |
| Data safety | One JSON file per store under `Model.dataDir`; atomic writes; unreadable files moved aside (`*.unreadable.json`), never overwritten. `PARLEY_DATA_DIR` overrides the folder. | Unit tests per store: corrupt file → moved aside, defaults loaded. |
| Testability | Pure logic in `nonisolated static` functions or value types (scoring, diff, streak, CSV), tested with Swift Testing in `Tests/ParleyTests`; views stay thin. | `make test` (swift test) in `make ci`. |
| Maintainability | One file per feature (`Progress.swift`, `Listening.swift`, `Conversation.swift`, `Writing.swift`, `Reading.swift`, `Transfer.swift`); shared UI pieces (`Card`, `StatTile`, `BackButton`, `WordCard`) reused. | Reviewer rubric; files < ~800 lines. |
| AI quality (FoundationModels) | `@Generable` structured outputs with `@Guide`; short instructions; one `LanguageModelSession` per conversation (keeps context); availability checked before showing the feature; errors shown inline with retry. Eval cases run by `make ai-eval` (needs Apple Intelligence; not in CI). | `make ai-eval` latency and correction hit-rate recorded in `benchmarks/`. |

## Components

```
Views.swift (shell: Route, Sidebar) ──► feature views
ActivityStore (activity.json)  ◄── PracticeSession, GrammarQuiz, Listening, Conversation, Writing, Reading  (XP events)
Listening: SessionClips (parse .md + -may.m4a/-mic.m4a offsets) → ClipPlayer (AVAudioPlayer, rate) → Dictation (WordDiff) / Shadowing (MicCheck + Answer.score)
Conversation: Scenario catalog → LanguageModelSession (Turn @Generable: reply, correction, better, tipVi) → Speaker (TTS) / MicCheck
Writing: prompt catalog → Critique @Generable → WritingStore (writing.json)
Reading: bundled passages + Story @Generable → selectable text → WordCard
Transfer: CSV codec (RFC 4180) ↔ VocabStore
```

## Data

- `activity.json`: `{ "days": { "2026-11-08": { "practice": 30, "grammar": 10, "listening": 20 } }, "goal": 50 }` — XP per skill per day (yyyy-MM-dd, local time).
- `writing.json`: `[ { id, date (ISO 8601), prompt, text, corrected, mistakes: [ { original, fix, explanation } ], level } ]`.
- XP: 10 per correct graded answer, 2 per wrong attempt, 15 per conversation turn, 30 per writing feedback, 20 per reading quiz.

## Threat model (local app)

Inputs are local files the user owns (session .md, CSV import) and model output. Risks: malformed/huge CSV (cap 20 000 rows, 5 MB; report errors per line), model output with unexpected shape (structured generation; empty fields tolerated), path traversal (none: fixed file names in `dataDir`). No network, no secrets.

## ADRs

- [ADR 0001](../../adr/0001-offline-only-ai.md) — on-device FoundationModels only; no cloud LLM.
