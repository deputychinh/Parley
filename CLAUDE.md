# Parley — project rules

Offline interpreter + English learning app for macOS 26+ (SwiftUI, SwiftPM executable, no Xcode project).

## Commands (full Xcode required — the Makefile sets `DEVELOPER_DIR`)

| Command | What |
| --- | --- |
| `make ci` | offline guard + release build (warnings = errors) + `swift test` — the gate for every commit |
| `make test` | Swift Testing suite in `Tests/ParleyTests` — run it via make: it sets `PARLEY_DATA_DIR` to a temp folder and a test fails on purpose without it |
| `make app` / `make run` / `make install` | `build/Parley.app` / open it / copy to /Applications |
| `make pipeline` | real speech recognition + translation on a `say` file |
| `make ai-eval` | on-device model checks (needs Apple Intelligence; not in CI) |
| `make shot ROUTE=<route> NAME=<file> [ARGS="--open x"]` | screenshot with seeded sample data → `docs/screenshots/` |
| `make shot-test` | checks shot.sh never stops another Parley and leaves nothing running |

## Rules

- **Never touch `~/Documents/Parley`** (the owner's data) from tests, scripts or screenshots: use `--data-dir <dir>` /
  `PARLEY_DATA_DIR`, `TestData.file(_:)` in tests, `Parley --seed <dir>` for sample data (only into a missing or empty folder outside the real one — `Seed.isAllowed`).
  (`open --env` does not reach the app; pass `--data-dir` as an argument.) Any GUI run with `--data-dir` — scripts,
  reviews, manual checks — uses `build/Parley-sandbox.app` (`make sandbox-app`, bundle id `com.david.parley.sandbox`):
  the real app refuses to start sandboxed, because macOS would save its window frames in the owner's settings.
- Run the seed / CLI checks with `.build/release/Parley`, not the binary inside `build/Parley.app`: from a shell the
  bundled binary blocks on a TCC prompt because the repo lives under ~/Documents.
- Offline only (ADR 0001): no network code in `Sources/`; AI = FoundationModels, checked with `available` first.
- UI copy in Vietnamese; code, docs and commits in English. Conventional Commits with `Refs: PARLEY-<n>`.
- Pure logic goes in value types / `nonisolated static` functions with Swift Testing tests; views stay thin.
- Stores: one JSON file per store in `Model.dataDir`, atomic writes, unreadable file moved aside to `*.unreadable.json`.
- Backlog `docs/backlog.md`, stories `docs/stories/`, current delivery `docs/delivery/001-learning-suite/status.md`.

## Delivery profile

| Key | Value |
| --- | --- |
| reply language | Vietnamese |
| frontend default | native SwiftUI (macOS) |
| backend default | none (local app) |
| mobile | none — macOS only |
| deploy target | local only (`make install`) |
