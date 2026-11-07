import Foundation
import Testing
@testable import Parley

/// PARLEY-7: CSV round trip and import rules (spec S7).
@Suite struct CSVTests {
    @Test func encodeQuotesOnlyWhenNeeded() {
        #expect(CSV.encode([["a", "b, c", "say \"hi\"", "two\nlines"]]) == "a,\"b, c\",\"say \"\"hi\"\"\",\"two\nlines\"\r\n")
    }

    @Test func parseHandlesQuotesLineBreaksBOMAndBlankLines() throws {
        let text = "\u{FEFF}term,meaning\r\n\"leak, memory\",\"rò \"\"rỉ\"\"\"\r\n\r\n\"multi\nline\",x\nlast,y"
        let rows = try CSV.parse(text)
        #expect(rows.map(\.fields) == [["term", "meaning"], ["leak, memory", "rò \"rỉ\""], ["multi\nline", "x"], ["last", "y"]])
        #expect(rows.map(\.line) == [1, 2, 4, 6]) // line numbers survive blank and multi-line rows
    }

    @Test func separatorDetection() {
        #expect(CSV.separator(for: "front\tback\nx\ty") == "\t")
        #expect(CSV.separator(for: "từ;nghĩa;ví dụ") == ";")
        #expect(CSV.separator(for: "term,meaning") == ",")
    }

    @Test func unterminatedQuoteIsAnError() {
        #expect(throws: Err.self) { try CSV.parse("a,\"b\nc,d") }
    }
}

@Suite struct VocabTransferTests {
    func item(_ term: String, mastered: Bool = false) -> VocabItem {
        var v = VocabItem(term: term, meaning: "nghĩa, có phẩy", termLanguage: "en-US", meaningLanguage: "vi", ipa: "/x/",
                          example: "He said \"\(term)\".", exampleTranslation: "dịch")
        v.mastered = mastered
        return v
    }

    @Test func exportThenImportRoundTrips() {
        let csv = VocabTransfer.export([item("leak"), item("deploy", mastered: true)])
        #expect(csv.hasPrefix("term,meaning,ipa,example,example_translation,mastered\r\n"))
        let r = VocabTransfer.parse(csv, existing: [])
        #expect(r.errors.isEmpty && r.duplicates == 0)
        #expect(r.items.map(\.term) == ["leak", "deploy"])
        #expect(r.items[0].meaning == "nghĩa, có phẩy" && r.items[0].example == "He said \"leak\"." && r.items[0].ipa == "/x/")
        #expect(!r.items[0].mastered && r.items[1].mastered && r.items[1].box == VocabItem.masteredBox)
    }

    @Test func ankiTSVWithoutHeaderUsesColumnOrder() {
        let r = VocabTransfer.parse("rollback\tkhôi phục\nestimate\tước lượng\n", existing: [])
        #expect(r.items.map(\.term) == ["rollback", "estimate"] && r.items[1].meaning == "ước lượng")
        #expect(r.items[0].ipa == Pronunciation.ipa("rollback")) // IPA filled in when missing
    }

    @Test func headerByNameInAnyOrderAndVietnameseNames() {
        let r = VocabTransfer.parse("nghĩa;từ\nhạn chót;deadline\n", existing: [])
        #expect(r.items.first?.term == "deadline" && r.items.first?.meaning == "hạn chót")
    }

    @Test func duplicatesAndErrorsAreReportedWithLineNumbers() {
        let text = "term,meaning\nleak,a\n,missing term\nLEAK,again\nAgenda,b\n" + String(repeating: "x", count: 201) + ",too long\n"
        let r = VocabTransfer.parse(text, existing: ["agenda"])
        #expect(r.items.map(\.term) == ["leak"])
        #expect(r.duplicates == 2)                          // "LEAK" repeated in the file, "Agenda" already saved
        #expect(r.errors == ["Dòng 3: thiếu từ.", "Dòng 6: từ dài quá 200 ký tự."])
        #expect(VocabTransfer.summary(r) == "Đã thêm 1 từ, bỏ qua 2 từ trùng, 2 dòng lỗi.")
    }

    @Test func badFilesImportNothing() {
        #expect(VocabTransfer.parse("", existing: []).items.isEmpty)
        #expect(VocabTransfer.parse("a,\"b", existing: []).errors.first?.contains("ngoặc kép") == true)
        let huge = String(repeating: "a,b\n", count: 1_300_000) // > 5 MB
        #expect(VocabTransfer.parse(huge, existing: []).errors == ["Tệp lớn hơn 5 MB."])
        let many = String(repeating: "a,b\n", count: VocabTransfer.maxRows + 2)
        #expect(VocabTransfer.parse(many, existing: []).errors.first?.contains("20000") == true)
    }
}

@MainActor @Suite struct VocabAddManyTests {
    @Test func addManySkipsKnownWordsAndSavesOnce() {
        let url = TestData.file("vocabulary.json")
        let s = VocabStore(file: url)
        s.add(VocabItem(term: "leak", meaning: "", termLanguage: "en-US", meaningLanguage: "vi", example: "", exampleTranslation: ""))
        let r = VocabTransfer.parse("term\nLeak\nsprint\nbacklog\n", existing: [])
        s.addMany(r.items)
        #expect(VocabStore(file: url).items.map(\.term).sorted() == ["backlog", "leak", "sprint"])
    }
}
