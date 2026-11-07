# PARLEY-9 — Debt from the PARLEY-1 review

Backlog row PARLEY-9. Findings from PARLEY-1 round 3 (8.5/10).

## Changes
- `scripts/shot.sh`: finds its instance by the unique temp data folder (`MacOS/Parley --data-dir <tmp>`), picks the
  window by PID (`window-id.swift` takes a PID), stops every instance with that folder from an `EXIT` trap (also on
  timeouts), starts with `-ApplePersistenceIgnoreState YES` and a forced window size so earlier runs can't leak a
  route or size. `SHOT_SEED=0` for empty states. `make shot-test` (decoy instance must survive, nothing left running).
- `make test` / `make bench` run with `PARLEY_DATA_DIR` = a temp folder; `dataDirFollowsTheEnvironmentInTests` pins it;
  `executableHonoursDataDirArgument` runs the real binary (`--print-data-dir`) to prove `--data-dir` beats the env.
- `Model.defaultDataDir` is the single source for the real folder (`Seed.realFolder` reuses it); Settings shows the folder in use.
- Move-aside tests for StudyStore and PronunciationStore (now through `StoreFile`, see PARLEY-2); seed test renamed.

## Evidence
| Finding | Evidence |
| --- | --- |
| shot.sh stops only its own PID | `make shot-test` → "shot-test: ok (decoy alive, no leftover instance)" |
| `--data-dir` hookup tested | `DataSafetyTests.executableHonoursDataDirArgument`, `dataDirFollowsTheEnvironmentInTests` |
| one source for the real folder | `Seed.realFolder == Model.defaultDataDir` asserted in tests |
| move-aside tests | `StoreRecoveryTests`, `StoreFileTests` |

## Review rounds
- Round 1 (with PARLEY-2): 7.0/10 — `--data-dir` arg path untested, shot.sh orphaned a late-starting instance and leaked window state, no story/CHANGELOG, unpushed. Fixed as above.

## Score
Pending review.
