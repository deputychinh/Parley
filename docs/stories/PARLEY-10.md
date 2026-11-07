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

## Score
Pending review.
