# 002 — plan

Appetite: 1 slice. Circuit breaker: if PARLEY-22 does not fit, cut it (screen ships without readings).

| Order | Item | Size | Why this order |
| --- | --- | --- | --- |
| 1 | PARLEY-20 Japanese in the live interpreter | S | smallest change, proves the JA speech + translation path end to end |
| 2 | PARLEY-21 Text & image translate screen | M | the main new value; riskiest UI work |
| 3 | PARLEY-22 Furigana | S | add-on to PARLEY-21 |

Design notes (no ADR change — everything on-device per ADR 0001):

- New `Translate.swift`: pure `TextTranslation` (split paragraphs, cap length, choose source by `NLLanguageRecognizer` constrained to supported languages), `OCR.text(in: CGImage)` via Vision `RecognizeTextRequest` (accurate, language correction, languages = chosen source or [ja, en, zh, ko, vi]), region capture via `/usr/sbin/screencapture -i -x <tmpfile>` (local process, no network).
- Translation through SwiftUI `.translationTask(config)` so the system handles pack downloads.
- `Furigana.segments(_:)` with `CFStringTokenizer` (`kCFStringTokenizerAttributeLatinTranscription` → hiragana); rendered by a small flow `Layout`.
- `Model.isEcho` tokenizes with `NLTokenizer(.word)` so CJK text yields words.
