# 002 — demo: translate any Japanese into Vietnamese or English, offline (v0.3.0)

Open: `/Applications/Parley.app` (installed with `make install`), or `make run` from the repo.

- **Phiên dịch trực tiếp** → language "Japanese (JP)" → target Vietnamese/English → Bắt đầu: meetings, YouTube, anime are transcribed in Japanese and translated live.
- **Dịch văn bản & ảnh** (new sidebar row): paste text, "Mở ảnh…", drag an image in, "Dán" a screenshot, or "Chụp vùng màn hình" and drag a box over manga, a game or a PDF → Japanese is read on device and translated paragraph by paragraph; "Cách đọc" shows furigana above kanji; "Sao chép bản dịch".
- CLI: `.build/release/Parley --translate-image shot.png --target en`, `.build/release/Parley --file talk.aiff --source ja_JP --target vi`.

Screenshots: `docs/screenshots/translate.png`, `translate-narrow.png`, `translate-empty.png`.
Cut / later: readings above 1 000 characters, live furigana, Japanese learning features (non-goals); debt PARLEY-23/24/25.
Feedback: none yet — recorded as "no feedback" for this slice.
