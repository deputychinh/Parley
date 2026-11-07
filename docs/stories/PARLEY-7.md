# PARLEY-7 — Vocabulary CSV import / export

Spec: [S7, AC7.1–AC7.2](../delivery/001-learning-suite/spec.md)

As a learner I want to move my word list in and out of Parley (Anki, Excel, backups) without losing anything.

## Design
- `Transfer.swift`: `CSV` (RFC 4180 encode/parse: quotes, `""`, line breaks inside quotes, CRLF, Excel BOM, blank lines,
  1-based line numbers, unterminated quote → error; separator detected from the first line: tab / `;` / `,`).
- `VocabTransfer.export` → `term,meaning,ipa,example,example_translation,mastered` (mastered `1/0`).
- `VocabTransfer.parse`: header row matched by name (English or Vietnamese aliases, any order; Anki `front/back`), else
  column order; skips words already saved or repeated in the file (case-insensitive, counted), reports empty or
  > 200-char terms with line numbers; limits 5 MB and 20 000 rows; fills IPA from CMUdict when missing; `mastered`
  puts the word in the 30-day box. Nothing is written for a file that fails to parse.
- `VocabStore.addMany` adds with one save. UI: "Nhập / Xuất" menu in Từ vựng (NSOpenPanel / NSSavePanel), alert with
  the summary and the first 8 line errors. Debug `--import <file>` for screenshots.

## AC → test traceability

| AC | Evidence |
| --- | --- |
| AC7.1 | `CSVTests.encodeQuotesOnlyWhenNeeded`, `VocabTransferTests.exportThenImportRoundTrips` (commas, quotes, mastered) |
| AC7.2 | `parseHandlesQuotesLineBreaksBOMAndBlankLines`, `separatorDetection`, `ankiTSVWithoutHeaderUsesColumnOrder`, `headerByNameInAnyOrderAndVietnameseNames`, `duplicatesAndErrorsAreReportedWithLineNumbers`, `badFilesImportNothing` (empty, unterminated quote, > 5 MB, > 20 000 rows), `VocabAddManyTests`; screenshot `vocabulary-import.png` |

## Review rounds
- Round 1 (independent): 7.5/10 — Anki "Notes in Plain Text" (`#separator:tab`, `#html:true`) imported junk; a `;` file with commas in meanings picked `,`; CRLF inside a field was exported unquoted (Swift's `\r\n` grapheme); formula cells (`= + - @`) exported raw; no BOM for Excel; a read-only store still reported "Đã thêm N từ".
  Fixed: `CSV.stripAnkiHeader` (honours `#separator`, keeps original line numbers); separator = consistent column count over the first rows, outside quotes, ties → tab, `;`, `,`; quoting checks `unicodeScalars`; `safeCell`/`unsafeCell` (`'` prefix, restored on import); BOM on export; `addMany` returns what it saved (0 when read-only or the save failed) and the alert says so. Tests: `TransferEdgeTests`, `ImportIntoReadOnlyStoreTests`.

## Score
Pending review.
