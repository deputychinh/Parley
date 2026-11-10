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
  change and calls `pad.autoTranslate(after: TranslatePad.autoDelay, …)` (600 ms; checked by `make wiring-guard`).
  Before the language list is loaded nothing runs (detection would fail).
- `TranslatePad.autoTranslate(after:…ready:)` holds the debounce (cancelled sleep → nothing) so it is tested; the view
  passes `ready: { !composing() }` (an input method with marked text is still converting).
- An automatic request on text whose language is unknown or equal to the target keeps the last result and shows no
  error (only "Dịch" / ⌘↩ do); VoiceOver hears only the end of an automatic request (`announcement(for:automatic:)`).
- "Tự dịch" checkbox next to "Dịch" (`@AppStorage("autoTranslate")`, default on).

## Review rounds
- Round 1 (independent): 8.0 — debounce untested (busy trigger, cancellation, delay survived mutation), error flashes
  and cleared result while typing, VoiceOver interrupted, input-method composition translated. Fixed as above.

## QA
| AC | Evidence |
| --- | --- |
| AC1, AC2, AC4 | `TranslatePadTests.autoTranslatesOnlyWhatChanged` (empty/blank, first time, already translated, whitespace only, other target, chosen source, more text) |
| AC2 failure, Xoá | `autoTranslateNeverRetriesAFailure` |
| AC3 | `textTypedDuringARequestIsTranslatedAfterIt`; `make wiring-guard` checks `busy: pad.busy` in the trigger |
| Debounce | `autoTranslateWaitsAndStopsWhenCancelled` (600 ms, cancelled → nothing, composing → nothing) |
| Quiet while typing | `automaticRequestsStayQuietOnUnknownLanguage`, `automaticRequestsAnnounceOnlyTheirEnd` |
| AC5 | view: toggle + empty-state copy; `translate.png`, `translate-narrow.png` (fits at 480 pt) |
| Wiring | `make wiring-guard` |
