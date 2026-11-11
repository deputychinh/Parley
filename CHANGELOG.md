# Changelog

All notable changes to Parley. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versions follow SemVer.

## [Unreleased]

### Added
- One-press mic in every speaking exercise (Học tập, Phát âm của tôi, Nói theo, Hội thoại AI): it stops when you stop talking (1.2 s of quiet, 2 s in conversation), shows a level ring, says so when it hears nothing for 6 s, and "Nghe lại giọng tôi" (⌥M) replays your attempt next to the model; attempts live in a temp folder emptied at launch and quit. (PARLEY-31)
- "Dịch văn bản & ảnh" translates on its own when text is pasted (⌘V) or typed and has settled for 0.6 s, or a language changes; "Tự dịch" turns it off. (PARLEY-26)
- "Mỗi ngày": "Đã biết hết" (asks first) and "Học hết" decide every word left at once. (PARLEY-29)
- "Học tập": ↩ triggers the main action — flip the card, "Đã nhớ", and "Tiếp" also after a typed answer (Space, 2 and ⌘N still work); grammar lessons start the exercises and close the result with ↩. (PARLEY-30)

### Changed
- Debug flag `--keys return,space,2` presses keys inside the app (screenshot and shortcut checks). (PARLEY-28)

### Fixed
- The Mini window scrolls all the way back to the last line after scrolling up (its rows were lazily estimated), and keeps the last 200 lines instead of 40, with a note when older lines are only in the main window. (PARLEY-27)

## [0.3.0] - 2026-11-10

### Added
- Kana readings (furigana) above the kanji of Japanese text on "Dịch văn bản & ảnh", with a toggle. (PARLEY-22)
- "Dịch văn bản & ảnh": type or paste text, open, drop or paste an image, or capture a screen region; on-device OCR and translation, language detected automatically; `Parley --translate-image`. (PARLEY-21)
- The live interpreter translates Japanese (and other languages written without spaces) into Vietnamese or English; `make pipeline` also runs a Japanese file. (PARLEY-20)

### Fixed
- Translation packs installed on macOS 27 (e.g. Japanese → Vietnamese) were reported as missing: builds now record the real SDK version, and `make build` checks it. (PARLEY-20)
- Speaker echo is merged for Japanese and Chinese speech; only English speech feeds "Phát âm của tôi". (PARLEY-20)

## [0.2.0] - 2026-11-08

### Fixed
- Screenshot and review runs (`--data-dir`) can no longer change the owner's settings or reminders. (PARLEY-13)
- `--data-dir` without a folder (or `--data-dir=x`) stops the app instead of using the real data folder. (PARLEY-10)
- Vocabulary import understands Anki "Notes in Plain Text" headers and `;`-separated files with commas; export keeps line breaks, adds a BOM for Excel and neutralizes formula cells. (PARLEY-7)
- Setting a lower daily goal counts today as met at once. (PARLEY-11)
- Listening: no double grading while the microphone stops; recognizer errors are shown. (PARLEY-12)
- Conversation: compliments are not offered as phrases to save; a stuck model reply times out after 30 s. (PARLEY-14)
- Learning data can't be lost to a damaged file any more: every store moves an unreadable file aside under a unique name, refuses to overwrite it if it can't, and shows save errors. (PARLEY-2)
- `shot.sh` stops only its own instance and ignores saved window state; `make shot-test` proves it. (PARLEY-9)

### Added
- *Đọc hiểu*: 8 graded passages (A2–C1) with questions and Vietnamese explanations, any word looked up by selecting it, read-aloud; reading XP counts once per passage per day. AI-written passages are not in this release (PARLEY-19). (PARLEY-6, PARLEY-18)
- *Cài đặt → Nhắc học*: an optional daily notification at a chosen time, only when today's XP goal is not met yet. (PARLEY-8)
- *Từ vựng → Nhập / Xuất*: export the word list as CSV and import CSV/TSV from Anki or Excel (header by name or column order, duplicates skipped, line-numbered errors). (PARLEY-7)
- *Luyện viết*: 12 prompts A2–C1 or a free topic; the on-device coach returns the corrected text (word diff), up to 8 mistakes with Vietnamese explanations and an estimated level; texts are kept in `writing.json`. (PARLEY-5)
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
