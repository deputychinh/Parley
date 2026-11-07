# Changelog

All notable changes to Parley. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versions follow SemVer.

## [Unreleased]

### Added
- *Tiến độ*: XP per skill per day, daily goal (10–200 XP), streak, 12-week heatmap, skill bars; sidebar ring + 🔥 streak. (PARLEY-2)
- Swift Testing suite (`make test`) and `make ci` gate (offline guard, warnings as errors). (PARLEY-1)
- `--data-dir` / `PARLEY_DATA_DIR`, `--seed <dir>` sample data and `make shot` screenshots that never touch the real data folder. (PARLEY-1)

### Changed
- Unit checks moved from `Parley --file` into `Tests/ParleyTests`; `--file` now runs only the real pipeline. (PARLEY-1)

## [0.1.0] - 2026-11-07

### Added
- Offline interpreter (system audio + microphone), bilingual history, vocabulary, daily words, topics, grammar A1–C1, practice modes and game, pronunciation tracking, mini window.
