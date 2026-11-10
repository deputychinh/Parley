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

## QA
Filled at step 4.
