import AppKit
import Foundation
import UniformTypeIdentifiers

// MARK: - CSV (RFC 4180) — pure, tested

enum CSV {
    /// Fields joined with `separator`; a field is quoted when it holds the separator, a quote or a line break.
    static func encode(_ rows: [[String]], separator: Character = ",") -> String {
        rows.map { row in
            row.map { f in
                f.contains(separator) || f.contains("\"") || f.contains("\n") || f.contains("\r")
                    ? "\"" + f.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : f
            }.joined(separator: String(separator))
        }.joined(separator: "\r\n") + "\r\n"
    }

    /// Tab, semicolon or comma — whichever appears most in the first line (Anki exports tabs, Excel in VN uses ";").
    static func separator(for text: String) -> Character {
        let first = text.prefix { $0 != "\n" && $0 != "\r" }
        let candidates: [Character] = [",", ";", "\t"]
        return candidates.max { a, b in first.count(where: { $0 == a }) < first.count(where: { $0 == b }) } ?? ","
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
    }

    static func export(_ items: [VocabItem]) -> String {
        CSV.encode([header] + items.map { [$0.term, $0.meaning, $0.ipa ?? "", $0.example, $0.exampleTranslation, $0.mastered ? "1" : "0"] })
    }

    /// Reads CSV/TSV text. With a header row (a column named term/word/front/từ), columns are matched by name;
    /// otherwise they are taken in order: term, meaning, ipa, example, example translation, mastered.
    /// Words already in `existing` (case-insensitive) or repeated in the file are skipped and counted.
    static func parse(_ text: String, existing: Set<String>, now: Date = .now) -> ImportResult {
        var result = ImportResult()
        guard text.utf8.count <= maxBytes else { result.errors = ["Tệp lớn hơn 5 MB."]; return result }
        let rows: [(line: Int, fields: [String])]
        do { rows = try CSV.parse(text) } catch { result.errors = [error.localizedDescription]; return result }
        guard !rows.isEmpty else { result.errors = ["Tệp không có dòng nào."]; return result }
        guard rows.count <= maxRows + 1 else { result.errors = ["Tệp có hơn \(maxRows) dòng."]; return result }

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
                return f[i].trimmingCharacters(in: .whitespacesAndNewlines)
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
        let r = VocabTransfer.parse(text, existing: Set(store.items.map(\.term)))
        store.addMany(r.items)
        return (VocabTransfer.summary(r), r.errors)
    }
}
