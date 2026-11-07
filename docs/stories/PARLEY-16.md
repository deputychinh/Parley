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

## Score
Pending review.
