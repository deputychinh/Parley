# 002 — Translate any Japanese into English or Vietnamese (offline)

Who: the owner, a Vietnamese speaker who meets Japanese in meetings, videos, games, manga, screenshots and documents.
Done means: anything Japanese the owner hears or sees on the Mac becomes English or Vietnamese without a network.

## Stories and acceptance criteria

### PARLEY-20 — Live interpreter hears Japanese `[macOS]`

1. Given source "Tiếng Nhật (Nhật Bản)" and target Vietnamese or English, when Japanese speech plays, then each sentence appears in Japanese with its translation (CLI evidence: `Parley --file ja.aiff --source ja_JP --target vi`).
2. Echo merge works for languages without spaces: the mic picking up the speakers' Japanese sentence yields one line, not two (unit tests with Japanese, Chinese and English; a different Japanese sentence is not an echo).
3. When the source is not English, mic speech is not recorded into "Phát âm của tôi".
4. `make pipeline` also runs a Japanese file (when a Japanese `say` voice exists) and fails on empty output.

### PARLEY-21 — "Dịch văn bản & ảnh" screen `[macOS]`

1. A sidebar row "Dịch văn bản & ảnh" under "Phiên dịch trực tiếp" opens the screen (`--route translate`); the interpreter toolbar does not show there.
2. Typing or pasting text and pressing "Dịch" (⌘↩) shows the translation paragraph by paragraph next to the source.
3. Images: "Mở ảnh…" (PNG, JPEG, HEIC, TIFF, PDF first page not required), drag-and-drop an image, "Dán" when the clipboard holds an image, and "Chụp vùng màn hình" (interactive region capture) all run on-device OCR and put the recognized text in the editor, then translate it.
4. Source language: "Tự nhận diện" (default) or a chosen language; target: any installed translation language, remembered (default Vietnamese). Detection that finds no supported language shows "Không nhận ra ngôn ngữ — hãy chọn ngôn ngữ nguồn".
5. Missing language pack → the system download sheet; still missing → a Vietnamese message, no crash.
6. Negative/boundary: empty input → "Dịch" disabled; image with no text → "Không tìm thấy chữ trong ảnh"; more than 20 000 characters → only the first 20 000 are translated and a notice says so; non-image file → refused with a message.
7. "Sao chép bản dịch" copies the whole translation.

### PARLEY-22 — Kana readings (furigana) `[macOS]`

1. When the source is Japanese, a toggle "Hiện cách đọc" shows hiragana above every word containing kanji (今日 → きょう, 会議 → かいぎ); kana-only words get no reading.
2. Pure function, unit-tested, including mixed text (Latin, digits, punctuation) and empty input.

## Quality targets

- OCR + translation of a screenshot with ≤ 300 Japanese characters: result in ≤ 3 s p50 on this Mac (M-series, packs installed), measured by a `Parley --translate-image <file>` CLI run timed 5×.
- No network code (offline guard in `make ci`).

## Non-goals

- Japanese learning features (vocabulary, practice, pronunciation for Japanese).
- Translate history, PDFs beyond images, live screen-region OCR (continuous), furigana in the live transcript.
