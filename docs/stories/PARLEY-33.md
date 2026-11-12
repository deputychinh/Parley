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
| 4 + least/list, each set's own hints (115 words) | **92 %** | **98 %** | 90 % | 90 % | 84 % | 83 % |

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

## Limits (said plainly)
- `hearOnly` words (den, doze, dare, dough, berry) are never asked for in "Nói". The other side of that coin: a learner
  who says "den" for "then" or "berry" for "very" is heard as the target and passes — the recognizer cannot tell. The
  hearing step still trains those contrasts.
- The recognizer, not a phoneme model, decides; a sound heard right in context can still be a weak sound.

## Review rounds
- Round 1 (independent): 6.0 — leave/live used CMUdict's /laɪv/ (feedback "âm /aɪ/ thành /i/"); an unknown word in
  the slot was skipped and passed; schwa described as /ʌ/; a word without the carrier was scored (AC4); no way out of
  "Nói" with a refused mic; spec silent on l–n, listening XP and voice rotation; the lesson link lost the round; the
  eval used other sets' hints. Fixed: least/list and a test that every item differs only in the set's sounds;
  unknown words are misses; changes keep stress (/ə/); no carrier → no score; "Bỏ qua" (→); spec updated; lessons
  open in a sheet; one voices lookup per lab; the eval says each word with its own set's hints; set rows labelled.
- Not verified: screenshots of "Nói" and the summary (screen locked during the round; `--keys` captures failed).
- Round 2 (same reviewer): 8.5 — summary counted skipped words as said; "leave – live" still in the set's text; the
  stop → score target not measured; no story row for least/list. Fixed: "Nói đúng x/y · bỏ qua z" and the trophy
  only on words said (`summaryCountsOnlyWordsSaid`); text "seat – sit"; `--sound-eval` times audio end → score:
  **p50 0.05 s, p90 0.05 s over 690 attempts** (target ≤ 1.5 s). With a live mic the end-pointer's 1.2 s of quiet
  comes first — by design (PARLEY-31), not processing time.
- Round 3 (same reviewer): **9.0 — ship.** M23 (half-round trophy rule) and M25 (percentile rounding) pinned right
  after. Open → PARLEY-39: screenshots of "Nói", feedback, "Bỏ qua" and the summary, and a live run with the owner's
  voice (UX and tests at 0.5 until then).

| # | Criterion | Score |
| --- | --- | --- |
| 1 | Requirements fit | 1 |
| 2 | Tests | 0.5 (no UI test or screenshot of the say flow) |
| 3 | Reliability | 1 |
| 4 | Security | 1 |
| 5 | Maintainability | 1 |
| 6 | UX | 0.5 (say flow never seen live) |
| 7 | Accessibility | 1 |
| 8 | Performance | 1 |
| 9 | Docs | 1 |
| 10 | Delivery | 1 |
| | **Total** | **9.0** |
