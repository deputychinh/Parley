# PARLEY-20 — Live interpreter hears Japanese

Delivery: [002-japanese-translate](../delivery/002-japanese-translate/spec.md) · ACs: spec "PARLEY-20" AC1–AC4 `[macOS]`

As the owner, I pick "Tiếng Nhật (Nhật Bản)" as the language I hear, so Japanese meetings and videos are translated into Vietnamese or English live and offline.

## Design
- No UI change: the source picker already lists SpeechTranscriber ∩ Translation languages (`Model.loadLanguages`).
- `Model.isEcho` tokenizes with `NLTokenizer(.word)` (Japanese/Chinese have no spaces).
- `Model.tracksPronunciation(_:)`: mic words go to "Phát âm của tôi" only for English sources.
- `Model.fileRunLanguages(_:)`: `Parley --file x --source ja_JP --target vi` for CLI evidence; `make pipeline` adds a Kyoko (ja_JP) run when that voice exists.
- **Root cause found on the way:** SwiftPM records the deployment target (26.0) as the binary's SDK version; on macOS 27 Translation then reports the JA→VI/EN packs as `supported` (not installed) and `translate` throws `notInstalled`, while a binary that records SDK 27 sees them `installed` (bisected: same code, swiftc vs SwiftPM, then `otool -l` LC_BUILD_VERSION). `scripts/link-flags.sh` passes `-platform_version macos 26.0 <sdk>` to the linker for `make` and `build.sh`; `make build` fails when the binary's SDK ≠ `xcrun --show-sdk-version`.

## QA
| AC | Evidence |
| --- | --- |
| AC1 Japanese speech → translation | `make pipeline`: `ja_JP: おはようございます。今日の会議を始めましょう。` → `vi: Chào buổi sáng. Hãy bắt đầu cuộc họp hôm nay.`; flags: `SessionFileTests.fileRunLanguagesFromArguments` |
| AC2 echo without spaces | `SessionFileTests.detectsSpeakerEchoWithoutSpaces` (JA, ZH, negative cases; failed before the change) + English cases in `detectsSpeakerEcho` |
| AC3 pronunciation only for English | `SessionFileTests.tracksPronunciationOnlyForEnglish` |
| AC4 pipeline runs Japanese, fails on empty | `make pipeline` (selfTest throws on empty heard/translated) |
| SDK guard | mutation: `make build SWIFT_FLAGS="-Xswiftc -warnings-as-errors"` → `binary records SDK 26.0, expected 27.0 …`, exit 1 |

Not checked: a GUI session with Japanese system audio (needs screen-capture permission on the real app); the CLI pipeline runs the same Transcriber + TranslationSession code.
