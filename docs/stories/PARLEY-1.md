# PARLEY-1 — Engineering baseline

Spec: [S1, AC1.1–AC1.3](../delivery/001-learning-suite/spec.md) · Design: [design.md](../delivery/001-learning-suite/design.md)

As the developer of Parley I want a one-command gate, real unit tests and safe screenshots so that every later item is
verified without risking the owner's data.

## Design
- `Package.swift`: `ParleyTests` test target on the executable target (`@testable import Parley`).
- `Model.dataDir` honours `--data-dir <path>` then `PARLEY_DATA_DIR`; `VocabStore(file:)` like the other stores.
- `Parley --seed <dir>` (`Seed.swift`) writes 12 words + one session; refuses `~/Documents/Parley`.
- `Makefile` (`ci` = offline guard + build with warnings as errors + test), `scripts/shot.sh` + `scripts/window-id.swift`.

## AC → test traceability

| AC | Evidence |
| --- | --- |
| AC1.1 | `make ci` → 21 tests in 7 suites passed; mutation `86_400→86_000` in `VocabItem.intervals` makes `make test`/`make ci` exit 2 |
| AC1.2 | `DataSafetyTests.seedRefusesTheRealFolderInAnySpelling` (exact, trailing `/`, `/.`, `..`, upper case, subfolder, symlink, parent) and `seedNeedsAMissingOrEmptyFolder`; mutation "guard only exact path" → test fails; `dataDirResolution` (`--data-dir` > `PARLEY_DATA_DIR` > default); stores tested with `TestData.file` |
| AC1.3 | `scripts/shot.sh vocabulary _probe` → screenshot shows the 12 seeded words, not the owner's; `seedWritesSampleDataAtomically` |

## Review rounds
- Round 1 (independent): 7.0/10 — seed guard bypassable with a trailing slash; no tests for data-dir resolution; seed writes not atomic. Fixed: `Seed.isAllowed` (missing/empty folder outside the real one, resolved + case-folded), `Model.resolveDataDir`, atomic writes, `--seed` without a path exits 1. Rejected: "the seed already ran on the real folder" — that session file existed before `Seed.swift` was written (owner's sample data, mtime 2026-11-07 18:21); the seed reuses its stamp on purpose.
- Round 2 (fresh reviewer): 8.0/10 — mutants survived (case-folding for a not-yet-existing subfolder, parent guard), `shot.sh` killed the owner's running Parley, unreadable folder counted as empty, CLI parsing untested. Fixed: tests for `REAL/NEW` and an empty parent (both mutants now fail the suite), `shot.sh` refuses to run while Parley is open, `isAllowed` only treats "no such file" as empty, `Seed.folder(in:)` tested.
- Round 3 (fresh reviewer, last allowed round): 8.5/10 — gate rule applied: requirements fit 1, security 1, no zeros → shipped; remaining findings filed as PARLEY-9.

## Score

| # | Criterion | Score |
| --- | --- | --- |
| 1 | Requirements fit | 1 |
| 2 | Test depth | 0.5 |
| 3 | Reliability | 0.5 |
| 4 | Security | 1 |
| 5 | Maintainability | 0.5 |
| 6 | UX | 1 |
| 7 | Accessibility | 1 (no UI change) |
| 8 | Performance | 1 (n/a) |
| 9 | Docs | 1 |
| 10 | Delivery | 1 |
| | **Total** | **8.5 / 10** (round 3 cap; debt PARLEY-9) |
