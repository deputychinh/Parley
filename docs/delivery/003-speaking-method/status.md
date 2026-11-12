# 003-speaking-method — status

Request (verbatim): "khi bạn nâng cấp phần học tập và các phần khác liên quan hãy tuân theo 1 phương pháp học tập để đảm
bảo mọi người có thể có trình độ nhanh nhất có thể đặc biệt là về chuyện nói tôi đang gặp vấn đề nói chưa tốt lắm" ·
"Thường xuyên phát âm sai và accent không tốt" · "Ok tốt tiếp tục vậy nhé"
Path: Full (light discover) — because it changes how several existing screens teach (Học tập, Phát âm, Luyện nghe,
Hội thoại AI, Mỗi ngày) around one method; no new repo.
Appetite: 2 slices of agent work · started 2026-11-12 · **Spent: 0 of 2 slices**
Platforms in scope: macOS (the only platform)
Status: doing

**Next action:** Build PARLEY-31 (one-press mic) with deliver-loop: story file, `EndPointer` tests first.

Resume: re-invoke `ship`; "Where am I?" reads this file and does the Next action.

## Delivery profile used

- reply language: Vietnamese (project CLAUDE.md)
- frontend / backend: native SwiftUI (macOS) / none (project CLAUDE.md)
- mobile: none — macOS only (project CLAUDE.md)
- autonomy: decide-and-record (~/.claude/CLAUDE.md)
- push policy: push every green commit (~/.claude/CLAUDE.md)
- review gate: independent review, ≥ 9/10, requirements fit = 1, security ≥ 0.5, ≤ 3 improve rounds (~/.claude/CLAUDE.md)
- deploy target: local only (`make install`) (project CLAUDE.md)

## Stages

| Stage | Status | Evidence / link |
| --- | --- | --- |
| Discover | done | brief.md (method + sources, spike: carrier sentence keeps minimal pairs apart) |
| Specify | done | spec.md (PARLEY-31…37, PARLEY-38 later) |
| Set up | n.a. | existing repo, `make ci` green (779484f) |
| Architect | done | plan.md design notes; no ADR change (ADR 0001 holds) |
| Plan | done | plan.md, backlog rows |
| Build | doing | |
| Verify | todo | |
| Demo | todo | |
| Release | todo | local only |
| Operate | n.a. | local app, no deploy target |
| Learn | todo | |

## Slices

| Slice | Items | Verified | Demo | Notified | Feedback → re-plan | Release |
| --- | --- | --- | --- | --- | --- | --- |
| 1 Sounds and feedback | PARLEY-31, 32, 33 | | | | | v0.4.0 |
| 2 Review, routine, rhythm, use | PARLEY-34, 35, 36, 37 | | | | | v0.4.1 |

## Progress log (one line per item or slice)

- 2026-11-12 triage — Full (light discover), 2 slices.
- 2026-11-12 owner added: IPA lessons, "mọi thứ về tiếng Anh" (→ PARLEY-38, later delivery), simplify the mic.
- 2026-11-12 PARLEY-31 one-press mic — shipped 7.0 under the round-3 rule (6.0 → 8.0 → 7.5 → 7.0), debt PARLEY-39.
- 2026-11-12 PARLEY-32 "Âm tiếng Anh" — shipped 9.5 (8.0 → 9.5).

## Rulings (decisions taken without asking)

- 2026-11-12 Goal is intelligibility and comprehensibility, not a native accent — because research (Munro & Derwing)
  shows they are separate and instruction moves comprehensibility far more than accent; reversible by a spec change.
- 2026-11-12 Stay offline (ADR 0001): scoring uses on-device speech recognition, word timings and audio analysis, no
  cloud pronunciation API — reversible only by a new ADR.

## Questions for the owner (only what nobody else can answer)

- none yet
