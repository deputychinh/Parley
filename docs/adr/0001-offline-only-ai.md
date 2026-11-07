# 0001 — On-device AI only (Apple FoundationModels), no cloud LLM

Date: 2026-11-08 · Status: accepted

## Context
Parley's promise is "hoàn toàn offline": meeting audio and text never leave the Mac. New learning features
(conversation role-play, writing feedback, graded reading) need a language model. Cloud models (Claude, GPT)
are stronger but need a network, an API key and a paid account, and would send the learner's text off-device.

## Decision
Use Apple's on-device `FoundationModels` (`SystemLanguageModel.default`) with structured (`@Generable`) output.
Features that need it check availability first and show a clear disabled state otherwise. No network code in `Sources/`.

## Consequences
- + Private, free, no keys; works on a plane.
- − Smaller model: corrections may miss subtle errors; output is capped (short turns, ≤ 250-word texts).
- − Needs Apple Intelligence enabled on macOS 26+; reading has bundled passages as a fallback.
- Revisit if the eval cases (`make ai-eval`) show a correction hit-rate below 60 %: an opt-in cloud adapter would then be a new ADR.
