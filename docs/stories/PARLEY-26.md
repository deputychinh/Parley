# PARLEY-26 — Translate on paste and typing

Requested by the owner after v0.3.0: "auto translate when I paste content without clicking Dịch". Path: Small.

As the owner, I paste (⌘V) or type Japanese into "Dịch văn bản & ảnh" and see the translation without pressing "Dịch".

## Acceptance criteria `[macOS]`
- AC1 Given "Tự dịch" is on (default), when text is pasted or typed into the editor and nothing changes for 0.6 s,
  then it is translated once, as if "Dịch" were pressed.
- AC2 Given the text, source and target equal the last request (whitespace aside), nothing is translated again — also
  after a failed request (no error loop); "Xoá" forgets the last request.
- AC3 Given a request is running, typing waits; when it ends, the newer text is translated.
- AC4 Changing the source or target language re-translates the current text.
- AC5 Given "Tự dịch" is off, only "Dịch" / ⌘↩ translate (the empty state says so); the choice is remembered.
- Out of scope: ⌘V of an *image* inside the text editor (the editor is plain text; the "Dán" button, drop, open and
  region capture already translate images on their own).

## Design
- `TranslatePad.lastRequest` (`Request`: trimmed text, source id, target id) is set by every accepted `translate`;
  `shouldAutoTranslate(source:target:)` = `canTranslate && lastRequest != request(input, …)`.
- `TranslateScreen` restarts a `.task(id: AutoTrigger)` on every input, language, busy, toggle or language-list
  change; it waits `TranslatePad.autoDelay` (600 ms), then `if pad.shouldAutoTranslate(…) { translate() }` (checked by
  `make wiring-guard`). Before the language list is loaded nothing runs (detection would fail).
- "Tự dịch" checkbox next to "Dịch" (`@AppStorage("autoTranslate")`, default on).

## QA
| AC | Evidence |
| --- | --- |
| AC1, AC2, AC4 | `TranslatePadTests.autoTranslatesOnlyWhatChanged` (empty/blank, first time, already translated, whitespace only, other target, chosen source, more text) |
| AC2 failure, Xoá | `autoTranslateNeverRetriesAFailure` |
| AC3 | `autoTranslatesOnlyWhatChanged` (busy → false); `busy` is part of `AutoTrigger`, so the task re-runs when a request ends |
| AC5 | view: toggle + empty-state copy; `translate.png`, `translate-narrow.png` (fits at 480 pt) |
| Wiring | `make wiring-guard` |
