# 001-learning-suite — status

Request (verbatim): "tiếp tục phát triển và hoàn thiện parley giúp tôi hãy làm cho nó thật hoàn hảo và đẩy đủ mọi tính năng hỗ trợ cho việc học tập và rèn luyện tiếng anh"
Path: Full — because the request is open-ended and adds several features to an existing app (existing repo: no CLAUDE.md/Makefile/backlog, so those are created first)
Appetite: 3 slices of agent work · started 2026-11-08 · **Spent: 0 of 3 slices**
Status: doing

**Next action:** PARLEY-1 final review (round 3), then apply PARLEY-2 (drafts: Progress.swift, ProgressTests.swift, wire_p2.py) and run its cycle.

Resume: re-invoke `ship`; "Where am I?" reads this file and does the Next action.

## Delivery profile used

- reply language: Vietnamese (~/.claude/CLAUDE.md)
- frontend / backend: native macOS SwiftUI app, no backend (repo)
- mobile: none — macOS only (repo; ruling below)
- autonomy: decide-and-record (~/.claude/CLAUDE.md)
- push policy: push every green commit when a remote exists (~/.claude/CLAUDE.md) — origin = github.com/deputychinh/Parley
- review gate: independent review, ≥ 9/10, requirements fit = 1, security ≥ 0.5, ≤ 3 improve rounds (~/.claude/CLAUDE.md)
- deploy target: local only (default) — `./build.sh install` to /Applications

## Stages

| Stage | Status | Evidence / link |
| --- | --- | --- |
| Discover | done | [brief.md](brief.md) |
| Specify | done | [spec.md](spec.md) |
| Set up | doing | PARLEY-1 (repo existed; adds tests, Makefile, CLAUDE.md) |
| Architect | done | [design.md](design.md), [ADR 0001](../../adr/0001-offline-only-ai.md) |
| Plan | done | [plan.md](plan.md), [backlog](../../backlog.md) |
| Build | doing | |
| Verify | todo | |
| Demo | todo | |
| Release | todo | local only |
| Operate | n.a. | local desktop app, no deploy target |
| Learn | todo | |

## Slices

| Slice | Items | Verified | Demo | Notified | Feedback → re-plan | Release |
| --- | --- | --- | --- | --- | --- | --- |
| 1 Habit + listening | PARLEY-1, 2, 3 | | | | | v0.2.0 |
| 2 Speak + write | PARLEY-4, 5 | | | | | v0.3.0 |
| 3 Read + data | PARLEY-6, 7, 8 | | | | | v0.4.0 |

## Progress log (one line per item or slice)

- 2026-11-08 PARLEY-1 — review r1 7.0 (seed guard bypass) → fixed 71f85c2; r2 8.0 (case/parent mutants, shot.sh killed running app) → fixed; 21 tests
- 2026-11-08 baseline — `swift build` with Xcode green; `Parley --file t.aiff` unit checks ok + STT/translation pipeline ok.

## Rulings (decisions taken without asking)

- 2026-11-08 "Perfect and every feature" is read as: cover all four skills (listen, speak, read, write) + habit/progress + data portability, offline — because that is the gap against ELSA, Duolingo, Anki and LingQ (brief.md); reversible by re-planning the backlog.
- 2026-11-08 On-device AI only (FoundationModels), no cloud LLM, so the `claude-api` skill is not used — because offline is Parley's core promise (ADR 0001).
- 2026-11-08 Build always with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (the machine's default is Command Line Tools, which lacks the SwiftUI macro plugins) — Makefile sets it.
- 2026-11-08 Tests and screenshots use `PARLEY_DATA_DIR` pointing to a temp/sample folder, never `~/Documents/Parley` (the owner's real data).
- 2026-11-08 No mobile app — Parley is a macOS app built on ScreenCaptureKit; no `mobile` key needed.

## Questions for the owner (only what nobody else can answer)

- none blocking.

## Cut scope and backlog findings

## Retro (every path; two lines for Quick and Bug)
