# 003 — Speaking method: spec

Who: Vietnamese speakers learning English with Parley, first of all the owner (often mispronounces, accent hard to
follow). Done means: Parley teaches every English sound, trains the ones that break understanding with the method
"Nghe → Nói → Nhại → Dùng → Ôn" (brief.md), tells the learner which sound went wrong, and brings it back until right —
offline. All ACs `[macOS]`.

## Slice 1 — sounds and feedback

### PARLEY-31 — One-press mic, everywhere, with "Nghe lại giọng tôi"

1. Every speaking exercise (Học tập "Luyện phát âm" and the speak step of "Thử thách", "Phát âm của tôi", Luyện nghe
   "Nói theo", Hội thoại AI, and the new sound lab) uses one mic control: press it or Space (↩ where Space types) to
   start; it stops by itself after ~1.2 s of silence once speech was heard, or when pressed again; a level meter shows it
   hears you.
2. No speech within 6 s → stops with "Không nghe thấy tiếng — kiểm tra micro rồi thử lại" (no score, no XP).
3. A hard cap per exercise (word ≈ 5 s, sentence = existing `listenLimit`, conversation 30 s) still ends it.
4. After an attempt, "Nghe lại giọng tôi" plays the learner's own recording; "Nghe mẫu" plays the model; both on keys
   (⌥R mẫu, ⌥M mine). Only the last attempt is kept, in a temp file deleted on the next attempt and on quit.
5. Mic permission denied → one Vietnamese message with "Mở Cài đặt".
6. The silence rule, the cap and the state machine are pure and unit-tested (frames of RMS levels in, stop reason out).

### PARLEY-32 — "Âm tiếng Anh": the IPA sounds, taught

1. A sidebar row "Âm tiếng Anh" (under Học) shows the US English sounds as a chart: short vowels, long vowels,
   diphthongs, consonants (voiceless/voiced pairs side by side) — all symbols CMUdict produces (`Pronunciation.ipa`).
2. Each sound opens a lesson: symbol, how to make it in Vietnamese (lips, tongue, voice, length), the Vietnamese sound
   it is confused with, 4–6 example words with the sound in start, middle and end position (IPA highlighted), each
   playable; a "Luyện âm này" button opens its minimal pairs (PARLEY-33).
3. Sounds that matter most for Vietnamese speakers carry a badge "Ưu tiên" (final consonants, -s/-ed, clusters, vowel
   length, /s/–/ʃ/; /θ/ /ð/ marked lower priority with the reason).
4. Every example word's IPA comes from CMUdict (unit test: each example contains its sound; each chart symbol appears
   in ≥ 1 CMUdict word).
5. Tapping an IPA string on a word card (Học tập, Mỗi ngày) is not required in this slice.

### PARLEY-33 — "Luyện âm": minimal pairs, hear then say

1. Contrast sets for Vietnamese speakers, ordered by priority: final stops (bye/bite/bike, see/seat/seed, …), -s/-ed
   endings (work/works/worked), clusters (pay/play, …), /s/–/ʃ/, /iː/–/ɪ/, /l/–/r/ … /θ/–/s/, /ð/–/d/ last. Each set
   ≥ 6 pairs; every word has a CMUdict pronunciation (unit test).
2. Nghe: 10 trials; a word from the set is spoken by a randomly chosen installed English voice (≥ 2 voices when
   installed, else the default voice with a note); the learner picks which word (keys 1/2/3); feedback right/wrong with
   both words replayable. Score kept per set.
3. Nói: the learner says the shown word in the carrier "I said ___ again." (shown); the recognized word in the slot is
   compared by CMUdict pronunciation (homophones pass: bye = buy); a miss shows what was heard and the sounds that
   differ, e.g. "Máy nghe ra **sip** /sɪp/ — âm /ʃ/ thành /s/", with the lesson link (PARLEY-32).
4. Nothing heard in the slot / carrier not recognized → "Chưa nghe rõ — nói lại cả câu “I said ship again.”", no score.
5. Results per contrast (trials, correct, last date) persist in `sounds.json` (atomic, unreadable file moved aside);
   XP goes to speaking (10 right, 2 attempt, as other drills).
6. `Parley --sound-eval`: every pair word said in the carrier by each installed English `say` voice must come back as
   itself ≥ 90% (CLI, prints misses; like `--ai-eval`, not in CI).

## Slice 2 — review, routine, rhythm, use

### PARLEY-34 — Sounds and words to review, spaced

1. Misses from every speaking drill (sound lab, Học tập speak, "Phát âm của tôi" retry, shadowing substitutions,
   conversation low-confidence words) go to one place: "Cần ôn" per sound (contrast set) and per word.
2. Review follows Leitner boxes like vocabulary (1, 3, 7, 14, 30 days); an item leaves the list after box 4, replacing
   the "3 in a row" rule (old data migrates: streak 3 → box 3).

### PARLEY-35 — "Luyện nói hôm nay": the routine and the method

1. A "Luyện nói" screen shows today's ~10-minute routine in method order: Học 1 âm (next priority sound not yet
   passed) → Nghe 10 → Nói 10 → Nhại 3 câu → Dùng: 2 lượt hội thoại nói → Ôn (due items); each step opens the existing
   screen and ticks off when done.
2. A short "Vì sao học theo thứ tự này" panel states the method in Vietnamese with the sources from brief.md.
3. Progress shows speaking broken down: sounds passed / total, items to review, minutes spoken this week.

### PARLEY-36 — Stress and intonation (circuit breaker: contours without a score)

1. In "Nói theo" (shadowing), the learner's pitch contour is drawn over the model's (same time scale), pitch by an
   on-device estimator over the recorded attempt.
2. For words of 2+ syllables, the stressed syllable (CMUdict) is marked; the attempt's loudest/highest syllable is
   compared; a mismatch says "Trọng âm nên ở âm tiết thứ 2: pho-TO-graph-er".

### PARLEY-37 — Pronunciation in conversation

1. In Hội thoại AI, words of a spoken turn with recognizer confidence < 0.5 are underlined with "Máy nghe chưa rõ",
   replayable (model and own voice), and go to "Cần ôn".
2. Shadowing and conversation use the learning accent setting (en_US default) instead of a hard-coded `en_US`.

## Quality targets

- Mic stop → score shown: ≤ 1.5 s p50 on this Mac (M-series), 10 timed sound-lab attempts (debug log timings).
- `--sound-eval`: ≥ 90% of pair words recognized as themselves per installed voice.
- No network code (offline guard); learner audio stays in the temp folder and is deleted after the next attempt.

## Non-goals

A native-accent score, on-device phoneme models, voices beyond the installed ones, Japanese speaking.
PARLEY-38 (backlog, later delivery): "mọi thứ về tiếng Anh" — a full course path (grammar, vocabulary, reading,
writing) on the same method.
