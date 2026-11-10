# PARLEY-22 — Kana readings (furigana)

Delivery: [002-japanese-translate](../delivery/002-japanese-translate/spec.md) · ACs: spec "PARLEY-22" AC1–AC2 `[macOS]`

As the owner, I see how to read the kanji of a Japanese sentence I translated, so I can say it or look it up.

## Design
- `Sources/Parley/Furigana.swift`: `Furigana.segments(_:)` (pure, `nonisolated static`) tokenizes with
  `CFStringTokenizer` (Japanese locale), turns each word's Latin transcription into hiragana, keeps okurigana and kana
  prefixes outside the reading (`split`) and keeps every character (gaps between tokens included), one segment per word. `RubyText` + `WrapLayout` draw the reading above each kanji run and wrap like a paragraph; VoiceOver reads
  the plain sentence.
- `TranslatePad.Pair.ruby` is filled only when the source language is Japanese, off the main actor (`readingsTask`,
  dropped when a newer request starts), and only up to `Furigana.limit` (1 000) characters — longer text shows a note
  instead (`readingsSkipped`). `TranslatePad.shownReading(_:enabled:)` decides what is drawn; the result card shows a
  "Cách đọc" checkbox (remembered: `showReadings`, default on).
- `RubyText` lays out one piece per word (`Furigana.pieces`; runs longer than 12 characters without a reading are cut
  so they wrap); `WrapLayout` caches child sizes; the result list is a `LazyVStack`. A context menu copies the source
  sentence or its translation (readings are drawn word by word, so the source is not selectable as one text).
- No reading for a word right after a digit or holding one (3月14日, 2人: counters are read differently, a wrong guess is worse than none);
  kanji beyond U+FFFF (𠮷) count as kanji.
- Known limit: readings come from the system dictionary per token; compounds can be read per part (火曜日 → かよう + ひ
  instead of かようび). The tooltip says the readings are suggestions.

## Review rounds
- Round 1 (independent): 7.0 — 20 000 characters froze the window ~3.5 s (one view per character, no layout cache,
  segments on the main actor); toggle untested and its state invisible; source not copyable with readings on; 14日 read
  か; 𠮷 missed. Fixed as above; W4 benchmark: 1 000 characters segment in 3 ms and lay out + render in 178 ms
  (`make bench`), segmenting guarded in `make test`.

- Round 2 (same reviewer): 8.5 — 2人 read "2れ́ん" (digits/accents accepted as kana, digit inside the token), stale
  readings guard and the view call sites untested, story named removed tests. Fixed: `isHiragana` check, no reading
  for tokens with a digit, `applyReadings(_:for:)` tested, `make wiring-guard` checks the two view call sites.

## QA
| AC | Evidence |
| --- | --- |
| AC1 hiragana above kanji words, none on kana-only words, toggle | `FuriganaTests.readsKanjiWords` (今日 → きょう, 会議 → かいぎ), `kanaLatinDigitsAndPunctuationGetNoReading`, `padAddsReadingsForShortJapaneseOnly`; screenshot `docs/screenshots/translate.png` (らいしゅう, かいぎ, ごご, しりょう, ぜんじつ, きょうゆう, ねが) |
| Toggle | `toggleChoosesReadingsOrPlainText`; `hasReadings` shows it (`padAddsReadingsForShortJapaneseOnly`); checkbox in `translate.png` |
| Limits and speed | `padAddsReadingsForShortJapaneseOnly` (over the limit → `readingsSkipped`), `clearDropsReadingsInFlight`, `BenchFurigana` (W4), `wrapsGreedily`, `longRunsWithoutReadingAreCutSoTheyWrap` |
| Counters, extension kanji | `noReadingRightAfterADigit` (3月14日, ３日, 2人), `kanjiBeyondTheBasicPlane` |
| Stale readings, view wiring | `staleReadingsAreIgnored`; `make wiring-guard` (view draws via `shownReading`, toggle shown on `hasReadings`) |
| AC2 pure, mixed text, empty | `keepsOkuriganaOutsideTheReading` (始め, お願い, mismatch keeps whole reading, nil reading), mixed Latin/digits/punctuation keeps every character, `emptyAndConversionHelpers` |
