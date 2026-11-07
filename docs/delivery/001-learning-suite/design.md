# 001 Learning suite — design

## Driving characteristics → decisions → fitness checks

| Characteristic | Decision | Fitness check |
| --- | --- | --- |
| Privacy / offline (product promise) | Only on-device frameworks: Speech, Translation, AVFoundation, FoundationModels, NaturalLanguage. No URLSession anywhere in `Sources/`. | `make ci` greps `Sources/` for `URLSession` and fails on a hit. |
| Data safety | One JSON file per store under `Model.dataDir`, read and written through `StoreFile`: atomic writes, save errors shown (`problem`), an unreadable file moved aside to a unique `*.unreadable-<stamp>-<id>.json`; if it can't be moved the store goes read-only. `--data-dir` / `PARLEY_DATA_DIR` override the folder. | `StoreFileTests`, `StoreRecoveryTests`, per-store move-aside tests. |
| Testability | Pure logic in `nonisolated static` functions or value types (scoring, diff, streak, CSV), tested with Swift Testing in `Tests/ParleyTests`; views stay thin. | `make test` (swift test) in `make ci`. |
| Maintainability | One file per feature (`Progress.swift`, `Listening.swift`, `Conversation.swift`, `Writing.swift`, `Reading.swift`, `Transfer.swift`); shared UI pieces (`Card`, `StatTile`, `BackButton`, `WordCard`) reused. | Reviewer rubric; files < ~800 lines. |
| AI quality (FoundationModels) | `@Generable` structured outputs with `@Guide`; short instructions; one `LanguageModelSession` per conversation (keeps context); availability checked before showing the feature; errors shown inline with retry. Eval cases run by `make ai-eval` (needs Apple Intelligence; not in CI). | `make ai-eval` latency and correction hit-rate recorded in `benchmarks/`. |

## Components

```
Views.swift (shell: Route, Sidebar) ──► feature views
ActivityStore (activity.json)  ◄── XPEvent from VocabStore.review, StudyStore (grammar, new words), PronunciationStore.retry,
                                    ListeningRun.grade (via the view), ConversationModel.send
Listening: Clips (parse .md + -may.m4a/-mic.m4a offsets) → ClipPlayer (AVAudioPlayer, rate) → ListeningRun.grade (WordDiff) for dictation and shadowing (MicCheck)
Conversation: Scenario catalog → LanguageModelSession (Turn @Generable: reply, correction, better, tipVi) → Speaker (TTS) / MicCheck
Writing: prompt catalog → Critique @Generable → WritingStore (writing.json)
Reading: bundled passages + Story @Generable → selectable text → WordCard
Transfer: CSV codec (RFC 4180) ↔ VocabStore
```

## Data

- `activity.json`: `{ "days": { "2026-11-08": { "vocabulary": 30, "grammar": 10, "listening": 20 } }, "goal": 50, "met": ["2026-11-08"] }` — XP per skill per day (yyyy-MM-dd, local time); `met` = days that reached the goal at the time (the streak counts these, so raising the goal never rewrites history).
- `writing.json`: `[ { id, date (ISO 8601), prompt, text, corrected, mistakes: [ { original, fix, explanation } ], level } ]`.
- XP (`XPEvent`): 10 per correct graded answer, 2 per wrong attempt, 5 per new daily word, 15 per conversation turn (voice → speaking, typed → writing); one listening XP event per sentence (retries don't add); 30 per writing feedback and 20 per reading quiz (planned).

## Threat model (local app)

Inputs are local files the user owns (session .md, CSV import) and model output. Risks: malformed/huge CSV (cap 20 000 rows, 5 MB; report errors per line), model output with unexpected shape (structured generation; empty fields tolerated), path traversal (none: fixed file names in `dataDir`). No network, no secrets.

## ADRs

- [ADR 0001](../../adr/0001-offline-only-ai.md) — on-device FoundationModels only; no cloud LLM.
