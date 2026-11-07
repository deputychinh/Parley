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
| AC1.1 | `make ci` → 14 tests in 6 suites passed; a failing `#expect` makes `swift test` (and `make ci`) exit non-zero |
| AC1.2 | `VocabStoreTests`, `PronunciationStoreTests` use `TestData.file`; `Seed.write` guard; `ls -lT ~/Documents/Parley` unchanged after `make shot` |
| AC1.3 | `scripts/shot.sh vocabulary _probe` → screenshot shows the 12 seeded words, not the owner's |

## Score
Pending review.
