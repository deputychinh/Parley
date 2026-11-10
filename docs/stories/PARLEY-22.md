# PARLEY-22 — Kana readings (furigana)

Delivery: [002-japanese-translate](../delivery/002-japanese-translate/spec.md) · ACs: spec "PARLEY-22" AC1–AC2 `[macOS]`

As the owner, I see how to read the kanji of a Japanese sentence I translated, so I can say it or look it up.

## Design
- `Sources/Parley/Furigana.swift`: `Furigana.segments(_:)` (pure, `nonisolated static`) tokenizes with
  `CFStringTokenizer` (Japanese locale), turns each word's Latin transcription into hiragana, keeps okurigana and kana
  prefixes outside the reading (`split`), keeps every character (gaps between tokens included) and merges runs without
  a reading. `RubyText` + `WrapLayout` draw the reading above each kanji run and wrap like a paragraph; VoiceOver reads
  the plain sentence.
- `TranslatePad.Pair.ruby` is filled only when the source language is Japanese; the result card shows a
  "Hiện cách đọc" toggle (remembered: `showReadings`, default on).
- Known limit: readings come from the system dictionary per token; compounds can be read per part (火曜日 → かよう + ひ
  instead of かようび). The tooltip says the readings are suggestions.

## QA
| AC | Evidence |
| --- | --- |
| AC1 hiragana above kanji words, none on kana-only words, toggle | `FuriganaTests.readsKanjiWords` (今日 → きょう, 会議 → かいぎ), `kanaLatinDigitsAndPunctuationGetNoReading`, `padAddsReadingsForJapaneseOnly`; screenshot `docs/screenshots/translate.png` (らいしゅう, かいぎ, ごご, しりょう, ぜんじつ, きょうゆう, ねが) |
| AC2 pure, mixed text, empty | `keepsOkuriganaOutsideTheReading` (始め, お願い, mismatch keeps whole reading, nil reading), mixed Latin/digits/punctuation keeps every character, `emptyAndConversionHelpers`, `mergesRunsWithoutReading` |
