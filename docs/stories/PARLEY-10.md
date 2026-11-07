# PARLEY-10 — Data-dir flag and shot-test (continues blocked PARLEY-9)

From PARLEY-9 round 3 (7.0, blocked: requirements fit 0.5).

## Changes
- `Model.dataDirFlag` is the single parser: absent / `.success(path)` / `.failure` for `--data-dir` without a value, a
  flag as value, or the `--data-dir=x` form. The app exits 2 on failure; `resolveDataDir` uses the same parser.
- `shot-test.sh` matches only `MacOS/Parley( |$)`, so a concurrent `swift test` (`MacOS/ParleyTests`) is not taken for
  a leftover shot instance.

## Evidence
| Finding | Evidence |
| --- | --- |
| `=` form and missing value refused | `malformedDataDirFlagIsRefused`; `executableHonoursDataDirArgument` checks exit 2 for `["--data-dir"]` and `["--data-dir=/tmp/y"]` |
| shot-test vs test helpers | `make shot-test` while `swift test` runs → ok |

## Review rounds
- Round 1 (independent): 8.0/10 — shot-test still failed when another session's shot instance started during the run; `resolveDataDir` returned the real folder for a malformed flag (safety rested on `Main`'s exit only); no CHANGELOG line.
  Fixed: shot-test only considers instances launched from this checkout's `build/Parley.app`; a malformed flag resolves to a throw-away temp folder (`parley-invalid-data-dir`), tested; CHANGELOG line added.

## Score
Pending review.
