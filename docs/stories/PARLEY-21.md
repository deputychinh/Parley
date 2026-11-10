# PARLEY-21 — "Dịch văn bản & ảnh"

Delivery: [002-japanese-translate](../delivery/002-japanese-translate/spec.md) · ACs: spec "PARLEY-21" AC1–AC7 `[macOS]`

As the owner, I paste Japanese text, open or drop a picture, or drag a box around anything on screen (manga, a game, a
PDF, a website screenshot), and read it in Vietnamese or English, offline.

## Design
- `Sources/Parley/Translate.swift`
  - Pure (`nonisolated static`, tested): `TextTranslation.prepare(_:)` (trim, cap at 20 000 characters, split into
    paragraphs, report truncation); `TextTranslation.detect(_:among:)` (kana → Japanese, else `NLLanguageRecognizer`
    hypotheses limited to translatable languages); `OCR.paragraphs(from:)` (join recognised lines into sentences: no
    space between CJK characters, new paragraph after 。！？.!? and closing quotes).
  - `OCR.recognize(_ image: CGImage, languages:)`: Vision `RecognizeTextRequest`, accurate, language correction.
  - `ScreenRegion.capture()`: `/usr/sbin/screencapture -i -x <temp file>` (local process; Esc → nil).
  - `TranslateScreen` view + `TranslatePad` (`@Observable`, main actor) holding input, source choice, target and a
    named state: `idle · reading image · translating · done(pairs, truncated) · failed(message)`.
  - Translation through `.translationTask(config)` so macOS shows the pack download sheet when needed.
- Route `.translate`, sidebar row under "Phiên dịch trực tiếp", `--route translate`; interpreter toolbar stays hidden.
- Target remembered in `AppDefaults.store` key `translateTarget` (default `vi`); source choice `translateSource`
  (default auto).
- CLI evidence and timing: `Parley --translate-image <file> [--target vi]` prints the OCR text, the translation and the
  elapsed time.

- "Dán" decision lives in `TranslatePad.paste(from:…)` so it is tested on a private pasteboard.
- UI fixes found on screenshots: pickers capped (a menu sizes to its longest language name and squeezed the button
  labels), `ViewThatFits` switches the actions to icons in a narrow window, the result card fills its column when empty.

## QA
| AC | Evidence |
| --- | --- |
| AC1 sidebar row, `--route translate`, no interpreter toolbar | `docs/screenshots/translate*.png`; `ReadingTests` route check (`.translate` hidden unless recording) |
| AC2 text → paragraph-by-paragraph translation, ⌘↩ | `TranslatePadTests.startsATranslationPerParagraph`; screenshot `translate.png` (3 paragraphs, JA auto-detected → VI) |
| AC3 images: open, drop, paste, region | OCR: `recognisesJapaneseInAnImage`, `imageTextGoesToTheEditorAndIsTranslated`, `pastesTextImagesOrNothing` (image on a private pasteboard); CLI `--translate-image` on a 6-line rendered screenshot joined lines into 3 sentences and translated them (VI and EN) |
| AC4 auto-detect / chosen source, remembered target, unknown language message | `detectsLanguages` (JA incl. kana-only, ZH, EN, VI, not-translatable → nil, empty), `explainsWhatItCannotDo` |
| AC5 missing pack | `.translationTask` shows the system sheet; on failure `run` re-checks `LanguageAvailability` and shows "Chưa có gói dịch …" — not exercised: every pack this Mac needs is installed |
| AC6 boundaries | empty → disabled (`emptyInputDoesNothing`); no text in image (`imageWithoutTextOrNotAnImage`); 20 000 / 20 001 chars (`cutsAtTheLimit`); non-image file (`refusesFilesThatAreNotImages`, CLI on README.md → `FAIL: Không mở được tệp này như một ảnh`, exit 1); empty clipboard message |
| AC7 copy translation | `TranslatePad.translation` joins targets; button visible in `translate.png` |
| Quality target ≤ 3 s p50 | `--translate-image` 5 runs: 16.56 s (cold: OCR + translation models load), 1.90, 1.87, 1.88, 1.87 s → p50 1.88 s |

Not checked by hand: the interactive region capture (needs a person to drag a box) and drag-and-drop from Finder.
