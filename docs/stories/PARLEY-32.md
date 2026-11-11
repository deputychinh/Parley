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
