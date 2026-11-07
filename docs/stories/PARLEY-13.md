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

## Review rounds
- Round 1 (independent): 7.0/10 — `ParleyCommands` and the WordCard popover used the owner's defaults; one shared sandbox domain wiped by every run. Fixed in d2f2f23 (every `@AppStorage` names `AppDefaults.store`, `defaults-guard`, per-process domain).
- Round 2 (fresh): 8.5/10 — per-pid domains never removed; `defaults-guard` missed `store: .standard` and `UserDefaults(suiteName:)`; story said "parley.sandbox". Another reviewer found that shot runs still wrote the main window frame into `com.david.parley` (the owner check had filtered `NSWindow Frame` lines — that evidence was wrong).
  Fixed: screenshots and reviews run `build/Parley-sandbox.app` (`make sandbox-app`, bundle id `com.david.parley.sandbox`), so anything macOS saves lands in that app's domain; owner defaults verified **byte-identical, window frames included**, before/after three shot runs; stale `parley.sandbox*` domains removed at a sandboxed launch and the own domain at quit (`SandboxCleanupTests`); `defaults-guard` rejects any `@AppStorage(` without `store: AppDefaults.store` and any `UserDefaults(`/`.standard` outside AppDefaults.swift; no "blocked" footer in a sandbox. The domain is `parley.sandbox.<pid>`.

## Score
Pending review.
