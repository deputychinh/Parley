# PARLEY-16 — Sandboxed runs, final pieces (continues blocked PARLEY-13)

## Changes
- The real app (`com.david.parley`) refuses to start with `--data-dir` (exit 2, message names `make sandbox-app`);
  CLAUDE.md and README say every `--data-dir` GUI run uses `build/Parley-sandbox.app`. CLI uses (`--seed`,
  `--print-data-dir`, tests without a bundle id) are unaffected.
- Stale `parley.sandbox.<pid>` domains are removed only when that process has exited (`processIsAlive`), plus the
  old shared `parley.sandbox`; the plist file is deleted, not just emptied (`removeDomain`).
- A sandboxed instance cleans its own domain on quit **and** on SIGTERM (shot.sh), via a dispatch signal source.
- `defaults-guard`: every `@AppStorage` line must match `@AppStorage("…", store: AppDefaults.store)`; no
  `.defaultAppStorage(.standard)`, no `CFPreferences`; `UserDefaults(`/`.standard` only in AppDefaults.swift.

## Evidence
| Finding | Evidence |
| --- | --- |
| real app refuses sandboxed runs | `theRealAppRefusesToRunSandboxed` |
| only finished runs cleaned, file deleted | `staleDomainsAreFoundButNotOurOwn` (running pid kept), `removeDomainDeletesTheFile`; after `make shot-test`, `~/Library/Preferences` holds no `parley.sandbox*.plist` (only the sandbox app's own `com.david.parley.sandbox.plist`) |
| owner settings | `defaults read com.david.parley` hash identical before/after (nothing filtered) |
Screenshot capture failed in this run because the display was locked ("could not create image from window"); the
instances still started and stopped cleanly.

## Review rounds
- Round 1 (independent): **9.0/10 — ship gate passed.** Notes (launch-path refusal untested, cfprefsd may rewrite an empty plist until the next sandboxed launch, more `defaults-guard` bypasses) → PARLEY-15.

## Score

| # | Criterion | Score |
| --- | --- | --- |
| 1 | Requirements fit | 1 |
| 2 | Test depth | 0.5 |
| 3 | Reliability | 0.5 |
| 4 | Security | 1 |
| 5 | Maintainability | 1 |
| 6 | UX | 1 |
| 7 | Accessibility | 1 |
| 8 | Performance | 1 |
| 9 | Docs | 1 |
| 10 | Delivery | 1 |
| | **Total** | **9.0 / 10** (round 1) |
