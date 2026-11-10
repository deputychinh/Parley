# PARLEY-20 — Live interpreter hears Japanese

Delivery: [002-japanese-translate](../delivery/002-japanese-translate/spec.md) · ACs: spec "PARLEY-20" AC1–AC4 `[macOS]`

As the owner, I pick "Tiếng Nhật (Nhật Bản)" as the language I hear, so Japanese meetings and videos are translated into Vietnamese or English live and offline.

## Design
- No UI change: the source picker already lists SpeechTranscriber ∩ Translation languages (`Model.loadLanguages`).
- `Model.isEcho` tokenizes with `NLTokenizer(.word)` (Japanese/Chinese have no spaces).
- `Model.tracksPronunciation(_:)`: mic words go to "Phát âm của tôi" only for English sources.
- `Model.fileRunLanguages(_:)`: `Parley --file x --source ja_JP --target vi` for CLI evidence; `make pipeline` adds a Kyoko (ja_JP) run when that voice exists.
- **Root cause found on the way:** SwiftPM records the deployment target (26.0) as the binary's SDK version; on macOS 27 Translation then reports the JA→VI/EN packs as `supported` (not installed) and `translate` throws `notInstalled`, while a binary that records SDK 27 sees them `installed` (bisected: same code, swiftc vs SwiftPM, then `otool -l` LC_BUILD_VERSION). `scripts/link-flags.sh` passes `-platform_version macos <Package.swift minimum> <sdk>` to the linker (same Xcode as the build, also from GNU Make 3.81's `$(shell)`); `scripts/check-sdk.sh` fails `make build` and `build.sh` when the binary's SDK ≠ `xcrun --show-sdk-version`; build.sh stops when the flags cannot be computed.

## Review rounds
- Round 1 (independent): 8.0 — build.sh could ship an SDK-26 binary silently, `$(shell)` used the CLT's SDK, README told readers to `swift build`, weak echo tests, untested call site. All fixed in round 1 (mutations: old split now fails 3 assertions; failing link-flags stops build.sh with exit 1).
- Final gate (fresh reviewer): **9.0/10 — ship gate passed.** Its call-site and `make bench` findings were fixed before shipping; `isEcho` cost for Japanese (~0.5 ms/call on the main actor), guard-script self-tests and a shared CLI-args type → PARLEY-23.

## QA
| AC | Evidence |
| --- | --- |
| AC1 Japanese speech → translation | `make pipeline`: `ja_JP: おはようございます。今日の会議を始めましょう。` → `vi: Chào buổi sáng. Hãy bắt đầu cuộc họp hôm nay.`; flags: `SessionFileTests.fileRunLanguagesFromArguments` |
| AC2 echo without spaces | `SessionFileTests.detectsSpeakerEchoWithoutSpaces` (JA, ZH, negative cases; failed before the change) + English cases in `detectsSpeakerEcho` |
| AC3 pronunciation only for English | `SessionFileTests.tracksPronunciationOnlyForEnglish` |
| AC4 pipeline runs Japanese, fails on empty | `make pipeline` (selfTest throws on empty heard/translated) |
| AC3 decision | `recordsPronunciation(from:kept:source:)` tested for mic/system, kept/echo, en/ja |
| SDK guard | mutations: `make build SWIFT_FLAGS="-Xswiftc -warnings-as-errors"` → `scripts/link-flags.sh failed`; minimum OS written as SDK → `… records SDK 26.0, expected 27.0`; build.sh without `$FLAGS` → check-sdk.sh exit 1; `make bench` now links with the same flags |
| AC3 call site | `make wiring-guard` (in `make ci`): reverting Model.swift to `if s == .mic, kept` → `Model.start must gate pronunciation.record with recordsPronunciation`, exit 2 |

Not checked: a GUI session with Japanese system audio (needs screen-capture permission on the real app); the CLI pipeline runs the same Transcriber + TranslationSession code.

## Score

| # | Criterion | Score |
| --- | --- | --- |
| 1 | Requirements fit | 1 |
| 2 | Test depth | 0.5 |
| 3 | Reliability | 1 |
| 4 | Security | 1 |
| 5 | Maintainability | 1 |
| 6 | UX | 1 |
| 7 | Accessibility | 1 |
| 8 | Performance | 1 |
| 9 | Docs | 0.5 |
| 10 | Delivery | 1 |
| | **Total** | **9.0 / 10** (final gate, fresh reviewer) |
