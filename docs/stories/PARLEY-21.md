# PARLEY-21 — "Dịch văn bản & ảnh"

Delivery: [002-japanese-translate](../delivery/002-japanese-translate/spec.md) · ACs: spec "PARLEY-21" AC1–AC7 `[macOS]`

As the owner, I paste Japanese text, open or drop a picture, or drag a box around anything on screen (manga, a game, a
PDF, a website screenshot), and read it in Vietnamese or English, offline.

## Design
- `Sources/Parley/Translate.swift`
  - Pure (`nonisolated static`, tested): `TextTranslation.prepare(_:)` (trim, cap at 20 000 characters, split into
    paragraphs, report truncation); `TextTranslation.detect(_:among:)` (`NLLanguageRecognizer` hypotheses limited to
    translatable languages); `OCR.paragraphs(from:)` (join recognised lines into sentences: no
    space between CJK characters, new paragraph after 。！？.!? and closing quotes).
  - `OCR.recognize(_:language:)`: Vision `RecognizeTextRequest`, accurate, language correction; auto = Japanese + English.
  - `OCR.image(at:)` / `loadImage(at:scoped:)`: local file URLs only (a link dragged from a browser is never fetched), decoded off the main actor.
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

## Review rounds
- Round 1 (independent): 7.0 — a dragged web link would be fetched by `NSImage(contentsOf:)` (ADR 0001); controls overflowed below ~650 pt; 5 of 13 mutations survived (stale-request guard, paste priority, truncation flag, kana rule); kana rule mislabelled "I love ラーメン"; Finder file copy pasted its name; cancellation shown as an error; capture without permission said "no text"; text lost when leaving the screen.
  Fixed: file URLs only + `data:` URL test; three-step controls (`ViewThatFits`, 480 pt screenshot); `receive(_:_:for:)`, `failureMessage`, `captureRegion(allowed:capture:)` made testable with tests; kana rule removed (NL already reads kana, kanji + の, half-width katakana); image files before text before image data; pad owned by ContentView; "Đã chép" confirmation. All 8 re-run mutations are caught.

- Final gate 1 (fresh reviewer): 7.5 — AC7 and the `.done` transition untested, a silent cancellation could leave the
  pad busy (it outlives the view), spinners after `.done`, no VoiceOver announcements, CJK/Latin join and the
  performance target unguarded. Fixed: `finish(for:)` / `cancelled(for:)` with tests, spinner only while translating,
  announcements, join tests, W5 in `benchmarks/plan.md`.

## QA
| AC | Evidence |
| --- | --- |
| AC1 sidebar row, `--route translate`, no interpreter toolbar | `docs/screenshots/translate*.png` (1200 and 480 pt); `ReadingTests` route check (`.translate` hidden unless recording) |
| AC2 text → paragraph-by-paragraph translation, ⌘↩ | `TranslatePadTests.startsATranslationPerParagraph`; screenshot `translate.png` (3 paragraphs, JA auto-detected → VI) |
| AC3 images: open, drop, paste, region | OCR: `recognisesJapaneseInAnImage`, `imageTextGoesToTheEditorAndIsTranslated`, `pastesTextImagesOrNothing` (image on a private pasteboard); CLI `--translate-image` on a 6-line rendered screenshot joined lines into 3 sentences and translated them (VI and EN) |
| AC4 auto-detect / chosen source, remembered target, unknown language message | `detectsLanguages` (JA incl. kana-only, ZH, EN, VI, not-translatable → nil, empty), `explainsWhatItCannotDo` |
| AC5 missing pack | `.translationTask` shows the system sheet; on failure `run` re-checks `LanguageAvailability`; the message is `failureMessage` (`failureMessages`: missing pack, other error, cancellation → nothing) |
| AC6 boundaries | empty → disabled (`emptyInputDoesNothing`); no text in image (`imageWithoutTextOrNotAnImage`); 20 000 / 20 001 chars (`cutsAtTheLimit`); non-image file (`refusesFilesThatAreNotImages`, CLI on README.md → `FAIL: Không mở được tệp này như một ảnh`, exit 1); empty clipboard message |
| AC7 copy translation | `finishesAndJoinsTheTranslation` (paragraphs joined one per line, `.done` only for the current request — the copy button shows in `.done`); "Đã chép" confirmation in the view |
| Cancellation | `cancellationNeverLeavesThePadBusy` (partial → idle and "Dịch" enabled, complete → done, stale → ignored) |
| VoiceOver | `announcesPhaseChanges`; per-paragraph spinner labelled "Đang dịch", shown only while translating |
| Quality target ≤ 3 s p50 | `--translate-image` 5 runs: 16.56 s (cold: OCR + translation models load), 1.90, 1.87, 1.88, 1.87 s → p50 1.88 s |

| Region capture | `regionCaptureNeedsPermissionAndIgnoresEsc` (no permission → message, capture not started; Esc → unchanged; image → read) |
| Offline (ADR 0001) | `neverLoadsNonFileURLs`: a `data:` PNG URL that NSImage can open is refused |

Not checked by hand: the interactive region capture itself (needs a person to drag a box) and drag-and-drop from Finder.
