# 001 Learning suite — brief

## Press release (headline)

**Parley turns every meeting you sit through into an English lesson — and now trains all four skills, offline.**
Vietnamese professionals who already use Parley to follow English meetings can now practise *listening*
on the exact sentences they heard, *speak* with an on-device AI partner that corrects them, *write* and
get explained corrections, *read* graded stories, and watch a streak and a heatmap grow — without any
audio or text leaving the Mac.

## Five customer questions

| Question | Answer |
| --- | --- |
| Who is the customer? | Vietnamese adults (many in IT) who use English at work and already run Parley in meetings (the owner first). |
| What is the problem? | Parley covers vocabulary, grammar and pronunciation flags, but not listening drills, speaking practice, writing feedback or reading; there is no view of progress, so habits break. |
| What is the benefit? | One offline app for the full loop: hear → understand → repeat → speak → write → review, with visible progress. |
| How do we know what they need? | The owner's request ("đầy đủ mọi tính năng hỗ trợ cho việc học tập và rèn luyện tiếng Anh"); gap against the reference products below. |
| What does the experience look like? | New sidebar items *Tiến độ*, *Luyện nghe*, *Hội thoại AI*, *Luyện viết*, *Đọc hiểu*; each works from data Parley already has or from the on-device model. |

## Product benchmark (from public product knowledge, not measured)

| Job | ELSA Speak | Duolingo | Anki | LingQ | Parley today → decision |
| --- | --- | --- | --- | --- | --- |
| Habit / progress | streaks, skill scores | streak, XP, daily goal | heatmap (add-on), stats | daily known-words goal | daily-words streak only → **activity log, XP goal, streak, 12-week heatmap, per-skill totals** |
| Listening | — | listen & type | — | listen to imported content | TTS "Nghe & viết" per word → **dictation + shadowing on real meeting audio, sentence level, speed control** |
| Speaking | phoneme scoring, AI role-play | AI role-play | — | — | word-level read-back → **on-device AI role-play with corrections** |
| Writing | — | sentence translation | — | writing correction | none → **AI writing coach, mistakes explained in Vietnamese** |
| Reading | — | stories | — | graded lessons + lookup | none → **AI graded stories with lookup + questions** |
| Data | — | — | CSV import/export | export | JSON only → **CSV import/export (Anki-compatible) + reminder** |

## Riskiest hypothesis

`HYPOTHESIS`: Apple's on-device model (FoundationModels) is good enough to correct learner English and hold a
role-play conversation in < 8 s per turn on Apple Silicon. Checked first in slice 2 with an eval set; fallback is
a disabled state with the reason, never a cloud call (offline is the product promise).

## Appetite

3 slices of agent work in this delivery (≈ one long sitting each). Scope inside each slice is cut, never the date.
