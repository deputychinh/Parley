# 003 — Speak clearly, fast: one method for Parley's learning

Owner's words: "tuân theo 1 phương pháp học tập … nhanh nhất có thể, đặc biệt là về chuyện nói" · "Thường xuyên phát âm
sai và accent không tốt" · "nên có các bài luyện tập như vậy và tôi cần học về các âm IPA và mọi thứ về tiếng Anh nữa;
phần bật âm thanh lên để nói cũng cần rà soát lại, làm đơn giản và hiệu quả".

## Press release (headline)

**Parley teaches you to be understood.** Each day a ten-minute speaking routine takes a Vietnamese speaker through the
sounds of English — every IPA sound with how to make it — and the ones that most often break understanding: final
consonants, endings, word stress. Hear them first, then say them, shadow them, use them in conversation; Parley brings
back exactly the sounds you still get wrong. One press of the mic, everywhere. All on the Mac, nothing sent anywhere.

## The method: "Nghe → Nói → Nhại → Dùng → Ôn" (hear, say, shadow, use, review)

| Step | What the learner does | Why (evidence) |
| --- | --- | --- |
| Goal | Be understood (intelligibility, comprehensibility), not a native accent | Accent and comprehensibility are separate; instruction moves comprehensibility far more than accent ([Munro & Derwing, redux](https://www.benjamins.com/catalog/bct.121.02mun)) |
| Priority | Sounds that break understanding first: final consonants and -s/-ed endings, clusters, vowel length, /s/–/ʃ/, then word and sentence stress; /θ/–/ð/ last | Typical Vietnamese-speaker errors: omitted finals and clusters, sound confusions, tonal transfer onto stress ([HPU TESOL 2023](https://www.hpu.edu/research-publications/tesol-working-papers/2023/1_trang_pham.pdf), [CTU](https://ctujs.ctu.edu.vn/index.php/ctujs/article/view/448)); /θ ð/ matter least for intelligibility (Jenkins' Lingua Franca Core — paraphrased from memory) |
| 0 Học âm (learn the sound) | Each IPA sound: symbol, how to place mouth and tongue (Vietnamese), example words, the Vietnamese sound it is confused with | Explicit instruction before practice; the IPA is already on every word card (CMUdict) but never taught |
| 1 Nghe (hear) | Tell minimal pairs apart, spoken by several voices | High-variability phonetic training improves perception and partly production ([Uchihara et al. 2024](https://www.cambridge.org/core/product/E38D8F5CE65DC708137B0E95F97C6BC7), [HVPT perception meta-analysis](https://resolve.cambridge.org/core/journals/studies-in-second-language-acquisition/article/high-variability-phonetic-training-hvpt-a-metaanalysis-of-l2-perceptual-training-studies/6ABB8C1F32D88D53EA8D05A4565E76F6/core-reader)) |
| 2 Nói (say) | Say each word in a carrier sentence; see which sound came out; replay own voice next to the model | Immediate, specific feedback; record-and-compare is what ELSA / BoldVoice offer ([review](https://www.alllanguageresources.com/elsa-speak/)) |
| 3 Nhại (shadow) | Shadow real sentences: rhythm, stress, intonation | Shadowing helps comprehensibility, fluency, prosody ([systematic review](https://ora.ox.ac.uk/objects/uuid:3104cae1-3a6b-400a-b173-de44384238d2)); prosody instruction wins when time is short ([Gordon & Darcy](https://www.jbe-platform.com/content/journals/10.1075/jslp.2.1.03gor)) |
| 4 Dùng (use) | Speak in the AI conversation; unclear words flagged | Transfer to free speech; the Coach already corrects grammar |
| 5 Ôn (review) | Sounds and words still wrong come back on a spaced schedule | Spaced practice: medium-to-large effect in L2 learning ([Kim & Webb 2022](https://eld.bl.uk/catalog/100152978253_0x000001)) |

## Five customer questions

1. **Who?** The owner (and Parley's learners): Vietnamese speakers who read and understand English at work but are often
   misunderstood when they speak.
2. **Problem?** Parley only checks that the recognizer produced the expected word: no sound-level feedback, no IPA
   lessons, no minimal pairs, no playback of one's own voice, no rhythm or stress, problem words only from live
   meetings; each speaking screen starts the mic differently, with fixed 3–4 s windows (codebase map, 2026-11-12).
3. **Most important benefit?** Knowing *which sound* went wrong and how to make it, hearing it against the model, and
   getting it back until it is right.
4. **How do we know?** Pass rate per sound rising over two weeks; fewer "unclear" words in live meetings
   (`PronunciationStore` average clarity) — `HYPOTHESIS`, no baseline yet.
5. **Experience?** One "Luyện nói" place with today's ten-minute routine and the IPA chart; every speaking exercise uses
   the same one-press mic and feeds the same list of sounds to review.

## Riskiest hypothesis and spike

The on-device recognizer must not "autocorrect" a wrong sound. Spike 2026-11-12 (`say` voices Samantha en_US and
Daniel en_GB, `Parley --file`): single words alone fail (empty, "sheep" → "She", "seat" → "Seed"); in the carrier
sentence "I said ___ again." every minimal pair came back as itself (ship/sip, think/sink, they/day, sheep, seat/seed/see,
bite/bike, play/pay, rice/rise, light/right), homophones aside (buy → "bye", right → "write" — compare CMUdict
pronunciations, not spellings). Still `HYPOTHESIS` for a real Vietnamese-accented voice: the owner's first sessions
are the test.

## Appetite

Two slices. Circuit breaker: if pitch analysis (stress and intonation) does not give stable curves, ship the contours as
"listen and compare" without a score.

## Non-goals (this delivery)

A native accent score; phoneme recognition models (none on-device); model voices other than the installed US/UK ones;
Japanese speaking practice. "Mọi thứ về tiếng Anh" beyond pronunciation (grammar, vocabulary, reading, writing courses)
→ backlog PARLEY-38 for a later delivery.
