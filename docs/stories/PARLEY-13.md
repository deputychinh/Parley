# PARLEY-13 — Sandboxed runs never touch the owner's settings or reminders

Found in the PARLEY-8 review: instances started with `--data-dir` (screenshots, reviews) shared the owner's defaults
domain (`com.david.parley`), so they read the owner's settings and rebuilt the owner's real reminders from sample data.

## Changes
- `AppDefaults`: a run is sandboxed when `--data-dir` (even malformed) or `PARLEY_DATA_DIR` is present; it then uses a
  `parley.sandbox` defaults domain wiped at launch. Every `UserDefaults.standard` use goes through `AppDefaults.store`,
  and `.defaultAppStorage(AppDefaults.store)` covers every `@AppStorage` in the main, mini and Settings scenes.
- Reminders: `reschedule`, `requestPermission` and `isDenied` do nothing in a sandboxed run.

## Evidence
| Finding | Evidence |
| --- | --- |
| sandbox detection | `SandboxDefaultsTests.sandboxIsDetectedFromFlagOrEnvironment` |
| tests use their own domain | `testsRunSandboxedWithTheirOwnDefaults` (`make test` sets PARLEY_DATA_DIR) |
| owner settings untouched by shots | `defaults read com.david.parley` (minus window frames) hashed before/after two `shot.sh` runs → identical; `parley.sandbox` domain empty afterwards |

## Score
Pending review.
