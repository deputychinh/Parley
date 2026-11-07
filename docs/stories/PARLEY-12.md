# PARLEY-12 — Debt from PARLEY-3 (round 3)

## Changes
- `MicCheck.stopping`: shadowing buttons are disabled until the recognizer's last result arrives; a grade for a
  sentence the learner already left (skip during the stop) is dropped.
- `Clip.playEnd(start:end:fileDuration:)` (tested): playback stops at the file end; a clip that starts past the end
  shows an error instead of silence.
- Recognition errors from the transcriber are shown (`MicCheck.error`) instead of swallowed.
- "Bỏ qua câu này" is a borderless secondary button.
- benchmarks/plan.md W2 → `make bench` / `BenchSeededClipTests` (best of 3; 18–93 ms measured).

## Evidence
`playbackStopsAtTheFileEnd`; the race and errors are view/AVFoundation paths checked by reading and a manual run.

## Score
Pending review.
