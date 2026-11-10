# 002 — verification (2026-11-10, main c2d7af2, macOS 27.0.1, M-series)

| AC | Evidence (run now) |
| --- | --- |
| PARLEY-20 AC1/AC4 Japanese speech → VI | `make pipeline`: `ja_JP: おはようございます。今日の会議を始めましょう。` → `vi: Chào buổi sáng. Hãy bắt đầu cuộc họp hôm nay.` (English run unchanged) |
| PARLEY-20 AC2/AC3 | `make ci`: 194 tests green, incl. `detectsSpeakerEchoWithoutSpaces`, `tracksPronunciationOnlyForEnglish`; `make wiring-guard` |
| Build records the real SDK | `otool -l .build/release/Parley` → `sdk 27.0`; `scripts/check-sdk.sh` in `make build` and `build.sh` |
| PARLEY-21 AC1–AC7 | `TranslateTests` (all green); screenshots `docs/screenshots/translate*.png` at 1200 and 480 pt |
| PARLEY-21 quality target (W5) | `Parley --translate-image` on a 6-line screenshot: 1.88 s, 1.87 s, 1.87 s (≤ 3 s); VI and EN output correct |
| PARLEY-22 AC1–AC2 | `FuriganaTests`; screenshot `translate.png` (らいしゅう, かいぎ, …, "Cách đọc" checkbox) |
| W4 furigana at the limit | `make bench`: segments 3 ms, layout + render 174 ms (< 400 ms) |
| Offline (ADR 0001) | `make offline-guard`; `neverLoadsNonFileURLs` |

Not verified by hand (needs a person): a live GUI session with Japanese system audio, dragging a box with "Chụp vùng màn hình", drag-and-drop from Finder.
