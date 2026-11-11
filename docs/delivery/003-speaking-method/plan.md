# 003 — plan

Appetite: 2 slices. Circuit breaker: PARLEY-36 ships pitch contours without a score if stress detection is unstable;
PARLEY-37 is cut first if the appetite runs out (filed as debt).

| Slice | Order | Item | Size | Why this order |
| --- | --- | --- | --- | --- |
| 1 | 1 | PARLEY-31 One-press mic + own-voice replay | M | every later drill depends on it; the owner asked to simplify it; replaces four hand-made auto-stop timers |
| 1 | 2 | PARLEY-32 "Âm tiếng Anh" IPA chart and lessons | M | step 0 of the method; content the sound lab links to |
| 1 | 3 | PARLEY-33 "Luyện âm" minimal pairs, hear then say | M | the riskiest new value (spike passed with TTS voices); needs 31 and 32 |
| 2 | 4 | PARLEY-34 Sounds and words to review, spaced | S | joins every drill's misses; needs 33's store |
| 2 | 5 | PARLEY-35 "Luyện nói hôm nay" routine + method panel | S | ties the steps together once they exist |
| 2 | 6 | PARLEY-36 Stress and intonation contours | M | riskiest DSP; breaker above |
| 2 | 7 | PARLEY-37 Pronunciation in conversation | S | first to cut |

Release boundary: v0.4.0 after slice 1 (local `make install`), v0.4.1 after slice 2.

## Design (no ADR change — everything on-device per ADR 0001)

- `MicCheck` becomes the one mic: `listen(language:limit:) async -> MicAttempt` runs until the end-pointer says stop
  (speech then 1.2 s quiet, nothing within 6 s, the cap) or `finish()` is called; the tap computes RMS for the meter
  and writes the attempt to a temp `.caf` (deleted on the next attempt and on quit). Pure `EndPointer` (levels + time →
  continue / stop reason) carries the rules and the tests. `MicButton` view: one control, level ring, Space/↩.
- `Sounds.swift`: `IPASound` table (symbol, ARPAbet, group, Vietnamese how-to, confused-with, priority, examples) and
  `ContrastSet` table (pairs, priority, carrier); `Pronunciation.phones(_:)` exposes CMUdict ARPAbet without stress;
  `SoundDiff.compare(target:heard:)` → same / differing phones (homophones equal); `SoundStore` (`sounds.json`).
- `Parley --sound-eval` speaks every pair word in the carrier with each installed English voice (`say -o` to temp) and
  runs it through `Transcriber`, printing misses; exit code fails under 90%.

## Security notes

- Learner audio: temp folder only (`FileManager.temporaryDirectory/parley-attempts/`), one file at a time, removed on
  the next attempt and at quit; never added to history or exports.
- `--sound-eval` runs `/usr/bin/say` with a fixed path and arguments from the bundled word list (no shell, no user
  input).
