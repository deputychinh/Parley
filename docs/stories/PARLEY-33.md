# PARLEY-33 — "Luyện âm": minimal pairs, hear then say

Delivery 003, slice 1. ACs: [spec.md § PARLEY-33](../delivery/003-speaking-method/spec.md) AC1–AC6.
Owner: "nên có các bài luyện tập như vậy" (hear, then say, sound-level feedback).

## Design
- `ContrastSet.all` (SoundLab.swift): 9 sets of ≥ 6 items, ordered by intelligibility priority (finals, -s/-ed,
  clusters, /s/–/ʃ/, /i/–/ɪ/, /l/–/n/, /v/–/b/–/w/, then /θ/ and /ð/ last); each links its lessons (PARLEY-32).
- `LabRound.make` draws 10 hearing trials (rotating installed English voices: high-variability training) and 10 words
  to say; `SoundLabView` runs Nghe (keys 1–3, ⌥R replay, both words replayable) then Nói (carrier "I said ___ again.",
  one-press mic from PARLEY-31, ⌥R model, ⌥M own voice), then a summary.
- `SoundDiff`: slot between "said" and "again"; compare CMUdict phones without stress (homophones pass); an edit
  script names the sound: "âm /ʃ/ thành /s/", "thiếu âm /t/", "thừa âm /s/"; the lesson of the first wrong sound is
  one click away. No carrier recognized → "Chưa nghe rõ — nói lại cả câu", no score.
- `SoundStore` (`sounds.json`, `StoreFile` atomic / move-aside): per set heard / heardRight / said / saidRight / last;
  passed at ≥ 10 spoken trials and ≥ 80 %; hearing → listening XP, saying → speaking XP (10 / 2).
- `Parley --sound-eval [set]`: every pair word in the carrier, each installed human English `say` voice, through the
  on-device recognizer; prints misses; fails under 90 % for a voice.
- Entry: "Âm tiếng Anh" → "Luyện âm — nghe rồi nói" (sets with progress, "Luyện tiếp") and "Luyện âm này" in a lesson.

## Recognizer findings (`--sound-eval`, 2026-11-12)
| Run | Samantha (US) | Daniel (GB) | Karen (AU) | Moira (IE) | Rishi (IN) | Tessa (ZA) |
| --- | --- | --- | --- | --- | --- | --- |
| 1 plain | 87 % | 93 % | 87 % | 90 % | 81 % | 79 % |
| 2 + pair hints (`AnalysisContext`), digits → words | 88 % | 94 % | 88 % | 91 % | 82 % | 81 % |
| 3 + rare words heard only, need → help | **92 %** | **98 %** | 91 % | 93 % | 85 % | 84 % |

Ruling: the gate is the US and UK model voices (the learner's targets; the recognizer is en_US). den, doze, dare,
dough and berry are always heard as then, those, there, go, very — `ContrastSet.hearOnly` keeps them in "Nghe" only,
so a right sound is never marked wrong. "needed" came back as "need it" → the item is help / helps / helped.

## QA
| AC | Evidence |
| --- | --- |
| AC1 sets, priority, CMUdict | `everyPairWordIsInCMUdictAndSetsAreBigEnough`; `docs/screenshots/sounds.png` |
| AC2 Nghe, several voices, keys 1–3 | `roundsRotateVoicesAndCoverTheSet`; `docs/screenshots/sound-lab.png`, `sound-lab-answer.png` (`--keys 1`: wrong pick → the right word, both replayable, +2 XP) |
| AC3 Nói, sound-level feedback, homophones | `sameSoundsPassEvenWhenSpelledOtherwise`, `missesNameTheSound`, `digitsAreWords`, `hintsAreTheWholePair`, `sayOnlyWordsTheRecognizerKeeps` |
| AC4 carrier not heard | `noCarrierMeansSayItAgain`, `slotIsTheWordsBetweenSaidAndAgain` |
| AC5 store, XP | `storeKeepsResultsAndLogsXP` |
| AC6 eval | `Parley --sound-eval`: run 3 above, `sound-eval: ok` |
| Not verified live | "Nói" with the owner's voice (screen locked, the sandbox app's mic prompt pending) → PARLEY-39 |
