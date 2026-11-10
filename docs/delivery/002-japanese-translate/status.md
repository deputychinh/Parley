# 002-japanese-translate — status

Request (verbatim): "có cách nào để tôi xây dựng 1 ứng dụng tương tự mục đích là có thể convert mọi tiếng nhật sang tiếng ah hhoạc tiếng việt" → "ok thế làm đi" (direction 1: extend Parley)
Path: Small — one clear new capability in an existing repo (Japanese in the live interpreter + a new text/image translate screen)
Appetite: 1 slice of agent work · started 2026-11-10 · **Spent: ⅔ of 1 slice**
Platforms in scope: macOS (native SwiftUI)
Status: doing

**Next action:** PARLEY-22 final re-review (branch `parley-22`, worktree `../parley-p21`); on ≥ 9 merge to main and ship; then verify, demo, release v0.3.0.

Resume: re-invoke `ship`; "Where am I?" reads this file and does the Next action.

## Delivery profile used

- reply language: Vietnamese (project CLAUDE.md)
- frontend / backend: native macOS SwiftUI, no backend (project CLAUDE.md)
- mobile: none — macOS only (project CLAUDE.md)
- autonomy: decide-and-record (~/.claude/CLAUDE.md)
- push policy: push every green commit when a remote exists (~/.claude/CLAUDE.md)
- review gate: independent review, ≥ 9/10, requirements fit = 1, security ≥ 0.5, ≤ 3 improve rounds (~/.claude/CLAUDE.md)
- deploy target: local only — `make install` (project CLAUDE.md)

## Stages

| Stage | Status | Evidence / link |
| --- | --- | --- |
| Discover | n.a. | Small path; capability probe below replaces it |
| Specify | done | [spec.md](spec.md) |
| Set up | n.a. | existing repo |
| Architect | done | no new ADR: everything stays on-device (ADR 0001); notes in [plan.md](plan.md) |
| Plan | done | [plan.md](plan.md), backlog PARLEY-20..22 |
| Build | doing | PARLEY-20 |
| Verify | todo | |
| Demo | todo | |
| Release | todo | local only |
| Operate | n.a. | local app, no deploy target |
| Learn | todo | |

## Slices

| Slice | Items | Verified | Demo | Notified | Feedback → re-plan | Release |
| --- | --- | --- | --- | --- | --- | --- |
| 1 Japanese | PARLEY-20, 21, 22 | | | | | v0.3.0 |

## Progress log (one line per item or slice)

- 2026-11-10 capability probe on this Mac: SpeechTranscriber lists `ja_JP` (model downloads on first use), Translation JA→EN and JA→VI `installed`, Vision `RecognizeTextRequest` read "今日は会議があります。明日東京へ行きます。" exactly, CFStringTokenizer readings 今日[きょう] 会議[かいぎ].

- 2026-11-10 PARLEY-20 — shipped 9.0 (round 1: 8.0, final fresh review 9.0) — cc8e9f6, 2a190c1 + ship commit; root cause found: SwiftPM records SDK 26.0 → Translation hides JA packs on macOS 27; debt → PARLEY-23

- 2026-11-10 PARLEY-21 — shipped 9.5 (round 1: 7.0 → 9.5; fresh final gate 7.5 → 9.5) — 838e6d2, 61d017c, 1ddea9f, cf808b5 + ship commit; drag-and-drop of a web link would have fetched it (fixed: local files only); debt → PARLEY-24

## Rulings (decisions taken without asking)

- 2026-11-10 Extend Parley rather than a new app — the user accepted the recommendation; the interpreter already accepts any SpeechTranscriber ∩ Translation language.
- 2026-11-10 Learning features stay English-only — the request is about translating Japanese, not learning it.
- 2026-11-10 Mic pronunciation tracking only for English sources — Japanese words would pollute the English "Phát âm của tôi" list.
- 2026-11-10 Translate screen keeps no history in v0.3.0 — not asked for; copy/export covers keeping a result.

## Questions for the owner (only what nobody else can answer)

- none
