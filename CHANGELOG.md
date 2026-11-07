# Changelog

All notable changes to Parley. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versions follow SemVer.

## [Unreleased]

### Fixed
- Learning data can't be lost to a damaged file any more: every store moves an unreadable file aside under a unique name, refuses to overwrite it if it can't, and shows save errors. (PARLEY-2)
- `shot.sh` stops only its own instance and ignores saved window state; `make shot-test` proves it. (PARLEY-9)

### Added
- *Hội thoại AI*: role-play 10 workplace and travel situations with Apple's on-device model at A2–C1; every turn is corrected (word diff), a more natural phrasing can be saved to vocabulary, and a summary lists what to remember. `make ai-eval` measures the coach. (PARLEY-4)
- *Luyện nghe*: dictation with word-by-word feedback and shadowing scored by on-device speech recognition, on the real audio of your saved meetings (or 187 curated sentences), at 0.75× or 1×. (PARLEY-3)
- *Tiến độ*: XP per skill per day, daily goal (10–200 XP), streak, 12-week heatmap, skill bars; sidebar ring + 🔥 streak. (PARLEY-2)
- Swift Testing suite (`make test`) and `make ci` gate (offline guard, warnings as errors). (PARLEY-1)
- `--data-dir` / `PARLEY_DATA_DIR`, `--seed <dir>` sample data and `make shot` screenshots that never touch the real data folder. (PARLEY-1)

### Changed
- Unit checks moved from `Parley --file` into `Tests/ParleyTests`; `--file` now runs only the real pipeline. (PARLEY-1)

## [0.1.0] - 2026-11-07

### Added
- Offline interpreter (system audio + microphone), bilingual history, vocabulary, daily words, topics, grammar A1–C1, practice modes and game, pronunciation tracking, mini window.
