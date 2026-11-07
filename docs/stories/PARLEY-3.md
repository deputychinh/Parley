# PARLEY-3 — Listening practice on real meeting audio

Spec: [S3, AC3.1–AC3.5](../delivery/001-learning-suite/spec.md) · Design: [design.md](../delivery/001-learning-suite/design.md)

As a learner I want to drill the sentences I actually heard in meetings so that I understand real speakers.

## Design
- `Listening.swift`: `Clips.from(notes:text:exists:)` turns each saved line with an offset (≥ 3 words) into a clip on its
  own recording (`-may.m4a` / `-mic.m4a`), ending at the next line of the same recording (max 15 s); `Clips.curated()`
  = topic example sentences read by the system voice when there is no meeting audio.
- `WordDiff.diff` (LCS over normalized words; case, punctuation and apostrophes ignored) marks expected words correct /
  wrong(typed) / missing and typed extras; score = correct ÷ expected words; pass ≥ 80 %.
- `ClipPlayer` (AVAudioPlayer, rate 0.75×/1×, stops at the clip end); `Speaker.speak(…, speed:)` for curated clips.
- Dictation (type → diff) logs *listening* XP; shadowing (mic → `MicCheck` → diff, auto-stop after the sentence's length)
  logs *speaking* XP. Errors (recording can't open, mic, silence) show inline; no history → curated source only.
- Route `.listening`, sidebar "Luyện nghe". Seed records its session with `say` so sample clips play real audio.
  Debug `--open dictation|shadowing`, `--type "<answer>"` for screenshots.

## AC → test traceability

| AC | Evidence |
| --- | --- |
| AC3.1 | `ClipTests.clipsRunToTheNextLineOfTheSameRecording`, `clipsNeedTheirRecording`, `curatedSentencesAlwaysExist`; `SeededClipTests` (real files); screenshot `listening.png` (5 real + 187 curated) |
| AC3.2 | clip end rules in `ClipTests`; `SeededClipTests` (clips within the file, no overlap); speed picker in screenshots; W2 open+seek 76 ms (< 300 ms) |
| AC3.3 | `WordDiffTests` (exact, substitution/missing/extra, apostrophes, empty, 80 % boundary, repeated words); screenshot `listening-dictation.png` |
| AC3.4 | shadowing uses the same `WordDiff` scoring + `WordDiff.pass`; screenshot `listening-shadowing.png`; mic run is manual (needs a person speaking) |
| AC3.5 | `ClipPlayer.error` / `MicCheck.error` / empty-mic message shown inline; no-history state in `ListeningView` (picker disabled + explanation) |

## Score
Pending review.
