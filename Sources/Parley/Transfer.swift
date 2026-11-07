import AppKit
import Foundation
import UniformTypeIdentifiers

// MARK: - CSV (RFC 4180) — pure, tested

enum CSV {
    /// Fields joined with `separator`; a field is quoted when it holds the separator, a quote or a line break.
    static func encode(_ rows: [[String]], separator: Character = ",") -> String {
        rows.map { row in
            row.map { f in
                // unicodeScalars: Swift treats "\r\n" as one Character, so `contains("\n")` would miss it
                f.contains(separator) || f.contains("\"") || f.unicodeScalars.contains(where: { $0 == "\n" || $0 == "\r" })
                    ? "\"" + f.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : f
            }.joined(separator: String(separator))
        }.joined(separator: "\r\n") + "\r\n"
    }

    /// The separator that splits the first rows into the same number (≥ 2) of columns, counted outside quotes;
    /// ties go to tab, then ";", then "," (Anki exports tabs; Excel in VN uses ";" and meanings often contain commas).
    static func separator(for text: String) -> Character {
        let lines = text.split(whereSeparator: \.isNewline).prefix(5).map(String.init)
        func counts(_ sep: Character) -> [Int] {
            lines.map { line in
                var inQuotes = false, n = 0
                for c in line { if c == "\"" { inQuotes.toggle() } else if c == sep, !inQuotes { n += 1 } }
                return n
            }
        }
        let order: [Character] = ["\t", ";", ","]
        let consistent = order.filter { sep in let c = counts(sep); return !c.isEmpty && c[0] > 0 && Set(c).count == 1 }
        if let best = consistent.max(by: { counts($0)[0] < counts($1)[0] }), counts(best)[0] > 0 {
            // prefer the earlier candidate on equal column counts
            return consistent.first { counts($0)[0] == counts(best)[0] } ?? best
        }
        return order.max { (counts($0).first ?? 0) < (counts($1).first ?? 0) } ?? ","
    }

    struct AnkiHeader: Equatable {
        var skipped = 0
        var separator: Character?
        var html = false
        var metaColumns: Set<Int> = []   // 0-based columns holding guid / notetype / deck / tags, not note fields
    }

    /// Anki's "Notes in Plain Text" starts with `#key:value` lines (`#separator:tab`, `#html:true`,
    /// `#deck column:2`, …); returns the text after them and what they declare.
    static func stripAnkiHeader(_ text: String) -> (body: String, header: AnkiHeader) {
        var lines = text.components(separatedBy: "\n")
        var h = AnkiHeader()
        while let first = lines.first, first.hasPrefix("#"), first.contains(":") {
            let parts = first.dropFirst().split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            let key = parts.first ?? "", value = parts.count > 1 ? parts[1] : ""
            switch key {
            case "separator": h.separator = ["tab": "\t", "comma": ",", "semicolon": ";", "pipe": "|", "space": " "][value]
            case "html": h.html = value == "true"
            case "guid column", "notetype column", "deck column", "tags column":
                if let n = Int(value), n > 0 { h.metaColumns.insert(n - 1) }
            default: break
            }
            lines.removeFirst()
            h.skipped += 1
        }
        return (lines.joined(separator: "\n"), h)
    }

    /// Anki fields with `#html:true`: line-break tags become new lines, other tags go, common entities are decoded.
    static func plainText(fromHTML s: String) -> String {
        var t = s.replacingOccurrences(of: "<br\\s*/?>|</div>|</p>", with: "\n", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (e, c) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&amp;", "&")] {
            t = t.replacingOccurrences(of: e, with: c)
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Rows with their 1-based starting line numbers; quoted fields may contain separators, quotes ("") and line breaks.
    /// Throws on an unterminated quote.
    static func parse(_ text: String, separator: Character? = nil) throws -> [(line: Int, fields: [String])] {
        let sep = separator ?? self.separator(for: text)
        var rows: [(line: Int, fields: [String])] = []
        var field = "", fields: [String] = []
        var inQuotes = false, line = 1, rowLine = 1
        var chars = Array(text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n"))
        if chars.first == "\u{FEFF}" { chars.removeFirst() } // Excel's UTF-8 BOM
        func endRow() {
            fields.append(field)
            if !(fields.count == 1 && fields[0].isEmpty) { rows.append((rowLine, fields)) } // skip blank lines
            field = ""
            fields = []
        }
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 1 } else { inQuotes = false }
                } else {
                    if c == "\n" { line += 1 }
                    field.append(c)
                }
            } else if c == "\"", field.isEmpty {
                inQuotes = true
            } else if c == sep {
                fields.append(field)
                field = ""
            } else if c == "\n" {
                endRow()
                line += 1
                rowLine = line
            } else {
                field.append(c)
            }
            i += 1
        }
        if inQuotes { throw Err("Dấu ngoặc kép chưa đóng (bắt đầu ở dòng \(rowLine)).") }
        if !field.isEmpty || !fields.isEmpty { endRow() }
        return rows
    }
}

// MARK: - Vocabulary import / export

enum VocabTransfer {
    static let header = ["term", "meaning", "ipa", "example", "example_translation", "mastered"]
    static let maxBytes = 5_000_000
    static let maxRows = 20_000

    struct ImportResult: Equatable {
        var items: [VocabItem] = []
        var duplicates = 0
        var errors: [String] = []   // "Dòng 7: thiếu từ."
        var fatal = false           // the whole file could not be read (nothing imported)
    }

    /// UTF-8 BOM first so Excel shows Vietnamese correctly; cells that a spreadsheet would run as a formula (or that
    /// already start with `'`) get one more `'`, which import removes again — a round trip never changes a value.
    static func export(_ items: [VocabItem]) -> String {
        "\u{FEFF}" + CSV.encode([header] + items.map {
            [$0.term, $0.meaning, $0.ipa ?? "", $0.example, $0.exampleTranslation].map(safeCell) + [$0.mastered ? "1" : "0"]
        })
    }

    static let formulaStarts: Set<Character> = ["=", "+", "-", "@", "\t", "\r", "'"]
    static func safeCell(_ s: String) -> String { s.first.map(formulaStarts.contains) == true ? "'" + s : s }
    static func unsafeCell(_ s: String) -> String {
        s.count > 1 && s.first == "'" && formulaStarts.contains(s[s.index(after: s.startIndex)]) ? String(s.dropFirst()) : s
    }

    /// Reads CSV/TSV text. With a header row (a column named term/word/front/từ), columns are matched by name;
    /// otherwise they are taken in order: term, meaning, ipa, example, example translation, mastered.
    /// Words already in `existing` (case-insensitive) or repeated in the file are skipped and counted.
    static func parse(_ text: String, existing: Set<String>, now: Date = .now) -> ImportResult {
        var result = ImportResult()
        func fail(_ message: String) -> ImportResult { result.errors = [message]; result.fatal = true; return result }
        guard text.utf8.count <= maxBytes else { return fail("Tệp lớn hơn 5 MB.") }
        let (body, anki) = CSV.stripAnkiHeader(text)
        var rows: [(line: Int, fields: [String])]
        do { rows = try CSV.parse(body, separator: anki.separator) } catch { return fail(error.localizedDescription) }
        rows = rows.map { row in // original line numbers; Anki meta columns dropped; HTML fields made plain
            let fields = row.fields.enumerated().filter { !anki.metaColumns.contains($0.offset) }
                .map { anki.html ? CSV.plainText(fromHTML: $0.element) : $0.element }
            return (line: row.line + anki.skipped, fields: fields)
        }
        guard !rows.isEmpty else { return fail("Tệp không có dòng nào.") }
        guard rows.count <= maxRows + 1 else { return fail("Tệp có hơn \(maxRows) dòng.") }

        let names = rows[0].fields.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        let aliases: [String: [String]] = [
            "term": ["term", "word", "front", "từ", "english"], "meaning": ["meaning", "back", "nghĩa", "definition", "vietnamese"],
            "ipa": ["ipa", "phiên âm", "pronunciation"], "example": ["example", "ví dụ", "sentence"],
            "example_translation": ["example_translation", "dịch ví dụ", "translation"], "mastered": ["mastered", "đã thuộc", "known"],
        ]
        let hasHeader = aliases["term"]!.contains { names.contains($0) }
        func column(_ key: String, fallback: Int) -> Int? {
            hasHeader ? names.firstIndex { aliases[key]!.contains($0) } : fallback
        }
        let col = (term: column("term", fallback: 0), meaning: column("meaning", fallback: 1), ipa: column("ipa", fallback: 2),
                   example: column("example", fallback: 3), exampleTr: column("example_translation", fallback: 4),
                   mastered: column("mastered", fallback: 5))
        var seen = Set(existing.map { $0.lowercased() })
        for (line, f) in rows.dropFirst(hasHeader ? 1 : 0) {
            func value(_ i: Int?) -> String {
                guard let i, f.indices.contains(i) else { return "" }
                return unsafeCell(f[i].trimmingCharacters(in: .whitespacesAndNewlines))
            }
            let term = value(col.term)
            guard !term.isEmpty else { result.errors.append("Dòng \(line): thiếu từ."); continue }
            guard term.count <= 200 else { result.errors.append("Dòng \(line): từ dài quá 200 ký tự."); continue }
            guard seen.insert(term.lowercased()).inserted else { result.duplicates += 1; continue }
            var item = VocabItem(term: term, meaning: value(col.meaning), termLanguage: "en-US", meaningLanguage: "vi",
                                 ipa: value(col.ipa).isEmpty ? Pronunciation.ipa(term) : value(col.ipa),
                                 example: value(col.example), exampleTranslation: value(col.exampleTr), session: nil)
            item.added = now
            if ["1", "true", "yes", "x", "có"].contains(value(col.mastered).lowercased()) {
                item.mastered = true
                item.box = VocabItem.masteredBox
                item.due = now.addingTimeInterval(VocabItem.intervals[VocabItem.masteredBox] * 86_400)
            }
            result.items.append(item)
        }
        return result
    }

    /// One-line Vietnamese summary for the alert.
    static func summary(_ r: ImportResult) -> String {
        if r.fatal { return "Không nhập được tệp." }
        var parts = ["Đã thêm \(r.items.count) từ"]
        if r.duplicates > 0 { parts.append("bỏ qua \(r.duplicates) từ trùng") }
        if !r.errors.isEmpty { parts.append("\(r.errors.count) dòng lỗi") }
        return parts.joined(separator: ", ") + "."
    }
}

// MARK: - Panels (UI glue)

@MainActor
enum VocabFiles {
    static func exportPanel(_ store: VocabStore) -> String? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "parley-tu-vung.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try Data(VocabTransfer.export(store.items).utf8).write(to: url, options: .atomic)
            return "Đã xuất \(store.items.count) từ ra \(url.lastPathComponent)."
        } catch {
            return "Không xuất được: \(error.localizedDescription)"
        }
    }

    static func importPanel(_ store: VocabStore) -> (summary: String, errors: [String])? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .tabSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return importFile(url, into: store)
    }

    static func importFile(_ url: URL, into store: VocabStore) -> (summary: String, errors: [String]) {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= VocabTransfer.maxBytes else { return ("Tệp lớn hơn 5 MB.", []) }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return ("Không đọc được tệp (cần UTF-8).", []) }
        var r = VocabTransfer.parse(text, existing: Set(store.items.map(\.term)))
        let added = store.addMany(r.items)
        guard added == r.items.count, store.problem == nil || added > 0 else {
            return ("Không lưu được từ vựng: \(store.problem ?? "kho từ đang ở chế độ chỉ đọc").", r.errors)
        }
        r.items = Array(r.items.prefix(added))
        return (VocabTransfer.summary(r), r.errors)
    }
}
