import Foundation
import Testing
@testable import Parley

/// PARLEY-5: the deterministic parts of the writing coach (spec S5). Model quality is `make ai-eval`.
@Suite struct WritingRulesTests {
    @Test func promptsCoverEveryLevel() {
        for level in CEFR.allCases { #expect(WritingPrompt.all.count { $0.level == level } >= 3, "AC5.1 \(level)") }
        #expect(Set(WritingPrompt.all.map(\.id)).count == WritingPrompt.all.count)
    }

    @Test func wordCountIgnoresPunctuationAndLines() {
        #expect(WritingRules.wordCount("Hello,  world!\nIt's me — again.") == 5)
        #expect(WritingRules.wordCount("   ") == 0)
    }

    @Test func lengthLimits() {
        let words = { (n: Int) in Array(repeating: "word", count: n).joined(separator: " ") }
        #expect(WritingRules.problem(with: words(19))?.contains("1 từ") == true)  // boundary below
        #expect(WritingRules.problem(with: words(20)) == nil)                      // min
        #expect(WritingRules.problem(with: words(250)) == nil)                     // max
        #expect(WritingRules.problem(with: words(251))?.contains("251") == true)   // boundary above
    }

    @Test func cleanDropsHallucinatedAndNoOpMistakes() {
        let text = "Yesterday we was busy and I learn a lot."
        let raw: [(original: String, fix: String, explanation: String)] = [
            ("we was", "we were", " Chủ ngữ số nhiều dùng 'were'. "),
            ("I learn", "I learned", "Quá khứ đơn."),
            ("they goes", "they go", "not in the text"),   // hallucinated → dropped
            ("busy", "busy", "no change"),                  // no-op → dropped
            ("WE WAS", "we were", "duplicate"),             // same span twice → dropped
            ("", "x", "empty"),
            ("a lot", "nhiều", "translated instead of corrected → dropped"),
        ]
        let m = WritingRules.clean(raw, in: text)
        #expect(m == [Mistake(original: "we was", fix: "we were", explanation: "Chủ ngữ số nhiều dùng 'were'."),
                      Mistake(original: "I learn", fix: "I learned", explanation: "Quá khứ đơn.")])
    }

    @Test func modelRewriteIsUsedOnlyWhileItIsACorrection() {
        let original = "Yesterday we was busy and I learn a lot about the new payment page."
        let mistakes = [Mistake(original: "we was", fix: "we were", explanation: ""), Mistake(original: "I learn", fix: "I learned", explanation: "")]
        let close = "Yesterday we were busy, and I learned a lot about the new payment page."
        #expect(WritingRules.correctedText(original: original, model: close, mistakes: mistakes) == close)
        let invented = "Subject: Absence today. Dear Manager, I am sick today and cannot work. " + close + " Best regards, Your Name"
        #expect(WritingRules.correctedText(original: original, model: invented, mistakes: mistakes)
                == "Yesterday we were busy and I learned a lot about the new payment page.") // rebuilt from mistakes
        let partial = "Yesterday we was busy, and I learned a lot about the new payment page." // model missed one listed fix
        #expect(WritingRules.correctedText(original: original, model: partial, mistakes: mistakes)
                == "Yesterday we were busy, and I learned a lot about the new payment page.")
        #expect(WritingRules.correctedText(original: original, model: "  ", mistakes: []) == original)
        #expect(WritingRules.correctedText(original: original, model: "Totally different words here.", mistakes: []) == original)
    }

    @Test func applyReplacesFirstOccurrenceInOrder() {
        #expect(WritingRules.apply([Mistake(original: "IS", fix: "are", explanation: "")], to: "they is here") == "they are here")
        // ambiguous span: never guessed ("This is fine and they is here" must not become "This are …")
        #expect(WritingRules.apply([Mistake(original: "is", fix: "are", explanation: "")], to: "This is fine and they is here")
                == "This is fine and they is here")
        #expect(WritingRules.apply([Mistake(original: "learn", fix: "learned", explanation: "")], to: "I relearn it") == "I relearn it") // lookbehind
        #expect(WritingRules.apply([Mistake(original: "zzz", fix: "a", explanation: "")], to: "abc") == "abc")
        let learn = [Mistake(original: "I learn", fix: "I learned", explanation: "")]
        #expect(WritingRules.apply(learn, to: "I learned it") == "I learned it")          // whole words only
        #expect(WritingRules.apply(learn, to: "Then I learn.") == "Then I learned.")
        #expect(WritingRules.apply([Mistake(original: "(a+b)", fix: "x", explanation: "")], to: "f (a+b) g") == "f x g") // regex chars
    }

    @Test func cleanKeepsOnlySafeFixes() {
        let text = "This is fine and they is here. Before the release we was busy. The page is more faster."
        let m = WritingRules.clean([("they is", "they are", ""), ("is", "are", "ambiguous"), ("we was", "were", "drops the subject"),
                                    ("more faster", "faster", "droppable word")], in: text)
        #expect(m.map(\.original) == ["they is", "more faster"])
        #expect(WritingRules.dropsMeaning(original: "we was", fix: "were"))
        #expect(!WritingRules.dropsMeaning(original: "discussed about", fix: "discussed"))
        #expect(WritingRules.occurrences(of: "is", in: "This is it, is it") == 2)
    }

    @MainActor @Test func timeoutFailsSlowWork() async throws {
        await #expect(throws: TimeoutError.self) { try await modelTimeout(0.05) { try await Task.sleep(for: .seconds(5)); return 1 } }
        #expect(try await modelTimeout(1) { 7 } == 7)
    }

    @Test func vietnameseDetection() {
        #expect(WritingRules.isVietnamese("đi"))
        #expect(WritingRules.isVietnamese("nhiều lỗi") && WritingRules.isVietnamese("Đúng"))
        #expect(!WritingRules.isVietnamese("we were") && !WritingRules.isVietnamese("naïve"))
    }

    @Test(arguments: [("B1", "B1"), ("b2+", "B2"), ("around C1 level", "C1"), ("A2/B1", "B1"), ("unknown", "?"), ("", "?")])
    func levelNormalization(raw: String, expected: String) {
        #expect(WritingRules.level(raw) == expected)
    }
}

@MainActor @Suite struct WritingStoreTests {
    func entry(_ text: String) -> WritingEntry {
        WritingEntry(prompt: "p", text: text, corrected: text, mistakes: [Mistake(original: "a", fix: "b", explanation: "c")],
                     level: "B1", summary: "s")
    }

    @Test func addPersistsNewestFirstAndLogsWritingXP() {
        let url = TestData.file("writing.json")
        let a = ActivityStore(file: TestData.file("activity.json"))
        let s = WritingStore(file: url, activity: a)
        s.add(entry("first"))
        s.add(entry("second"))
        let reloaded = WritingStore(file: url)
        #expect(reloaded.entries.map(\.text) == ["second", "first"])
        #expect(reloaded.entries[0].mistakes.first?.fix == "b")
        #expect(a.data.days[StudyStore.day(.now)] == ["writing": 60]) // AC5.3 + XP 30 each
        s.remove(s.entries[0].id)
        #expect(WritingStore(file: url).entries.map(\.text) == ["first"])
    }

    @Test func unreadableFileIsKept() throws {
        let url = TestData.file("writing.json")
        try Data("[{".utf8).write(to: url)
        #expect(WritingStore(file: url).entries.isEmpty && TestData.asideFiles(of: url).count == 1)
    }

    @Test func essayXP() { #expect(XPEvent.essay.skill == .writing && XPEvent.essay.xp == 30) }

    @Test func evalEssayHasThePlantedMistakes() {
        #expect(AIEval.planted.allSatisfy { AIEval.essay.contains($0) })
    }
}
