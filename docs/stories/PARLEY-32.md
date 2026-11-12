# PARLEY-32 — "Âm tiếng Anh": the IPA sounds, taught

Delivery 003, slice 1. ACs: [spec.md § PARLEY-32](../delivery/003-speaking-method/spec.md) AC1–AC5.
Owner: "tôi cần học về các âm IPA".

## Design
- `IPASound` (Sounds.swift): 41 sounds = every symbol `Pronunciation.ipa` writes (39 ARPAbet phones, schwa /ə/ and
  /ɚ/ as their own sounds); group, priority for Vietnamese speakers, how-to and "người Việt hay nhầm" in Vietnamese,
  4 CMUdict example words each. `Pronunciation.phones` / `symbol` expose CMUdict per phone.
- `SoundsView` chart → `SoundLesson` (symbol, how-to, confusions, examples with the sound highlighted in the IPA,
  each playable). Sidebar row "Âm tiếng Anh", `--route sounds [--open SH]`.
- "Luyện âm này" (link to the minimal pairs) arrives with PARLEY-33.

## QA
| AC | Evidence |
| --- | --- |
| AC1 chart covers every CMUdict symbol once | `SoundsTests.chartCoversEveryCMUdictSoundOnce`; `docs/screenshots/sounds.png` |
| AC2 lesson | `docs/screenshots/sound-sh.png`; `lessonHighlightsOnlyTheSound` |
| AC3 priorities | `prioritiesFollowTheMethod` |
| AC4 examples contain their sound | `everyExampleContainsItsSound` (caught "around" = ER0 AW1 N D and "beyond" — replaced) |

## Review rounds
- Round 1 (independent, with PARLEY-33): 8.0 — pairs could split across rows; the chart sat below the practice list;
  /s/ had no middle example; G "normal" among high final stops; AH and IY confusion texts. Fixed: the pair group lays
  out voiceless + voiced side by side (`IPASound.pairs`), chart first and practice after it, "basic", G high, texts;
  tests `examplesShowWhereTheSoundSits`, `pairsSitSideBySide`, P/B/G in the priority test.
- Round 2 (same reviewer): **9.5 — ship.** Open: retake `sounds.png` with the chart when the screen is unlocked.

| # | Criterion | Score |
| --- | --- | --- |
| 1 | Requirements fit | 1 |
| 2 | Tests | 1 |
| 3 | Reliability | 1 |
| 4 | Security | 1 |
| 5 | Maintainability | 1 |
| 6 | UX | 1 |
| 7 | Accessibility | 1 |
| 8 | Performance | 1 |
| 9 | Docs | 0.5 (`sounds.png` predates the new layout) |
| 10 | Delivery | 1 |
| | **Total** | **9.5** |
