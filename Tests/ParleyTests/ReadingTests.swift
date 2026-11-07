import Foundation
import Testing
@testable import Parley

/// PARLEY-6: graded reading (spec S6). AI generation quality is checked by hand; its output goes through the same rules.
@Suite struct ReadingRulesTests {
    @Test func bundledPassagesAreUsable() {
        let r = Library.readings
        #expect(r.count >= 8 && Set(r.map(\.id)).count == r.count)
        for level in ["A2", "B1", "B2", "C1"] { #expect(r.count { $0.level == level } >= 2, "level \(level)") }
        for p in r {
            #expect(ReadingRules.problem(with: p) == nil, "\(p.id): \(ReadingRules.problem(with: p) ?? "")")
            #expect(ReadingRules.validQuestions(p.questions).count == p.questions.count, "\(p.id) has an invalid question")
            #expect(ReadingRules.paragraphs(p.text).count >= 3, "\(p.id) paragraphs")
        }
    }

    @Test func invalidQuestionsAreDropped() {
        let good = ReadingQuestion(prompt: "Q?", options: ["a", "b", "c", "d"], answer: " B ", explainVi: "")
        let qs = [good,
                  ReadingQuestion(prompt: "", options: ["a", "b", "c", "d"], answer: "a", explainVi: ""),     // no prompt
                  ReadingQuestion(prompt: "Q?", options: ["a", "b", "c"], answer: "a", explainVi: ""),          // 3 options
                  ReadingQuestion(prompt: "Q?", options: ["a", "A", "c", "d"], answer: "a", explainVi: ""),     // duplicate
                  ReadingQuestion(prompt: "Q?", options: ["a", "b", "c", "d"], answer: "e", explainVi: "")]     // answer missing
        let v = ReadingRules.validQuestions(qs)
        #expect(v.count == 1 && v[0].answer == "b") // answer normalized to the option's spelling
    }

    @Test func passageProblems() {
        let q = ReadingQuestion(prompt: "Q?", options: ["a", "b", "c", "d"], answer: "a", explainVi: "")
        let text = Array(repeating: "word", count: 100).joined(separator: " ")
        var p = Passage(id: "x", level: "B1", title: "T", topic: "t", text: text, questions: [q, q])
        #expect(ReadingRules.problem(with: p) == nil)
        p.questions = [q]
        #expect(ReadingRules.problem(with: p)?.contains("câu hỏi") == true)
        p.questions = [q, q]; p.text = "too short"
        #expect(ReadingRules.problem(with: p)?.contains("từ") == true)
        p.text = text; p.title = " "
        #expect(ReadingRules.problem(with: p)?.contains("tiêu đề") == true)
    }

    @Test func scoreCountsCorrectAnswers() {
        let qs = [ReadingQuestion(prompt: "1", options: ["a", "b", "c", "d"], answer: "a", explainVi: ""),
                  ReadingQuestion(prompt: "2", options: ["a", "b", "c", "d"], answer: "b", explainVi: "")]
        #expect(ReadingRules.score([0: "a", 1: "c"], qs) == 1 && ReadingRules.score([:], qs) == 0)
    }
}

@MainActor @Suite struct ReadingStoreTests {
    @Test func answersLogReadingXPAndBestScoreIsKept() {
        let url = TestData.file("reading.json")
        let a = ActivityStore(file: TestData.file("activity.json"))
        let s = ReadingStore(file: url, activity: a)
        s.answer(correct: true)
        s.answer(correct: false)
        s.finish("a2-new-job", score: 2)
        s.finish("a2-new-job", score: 1) // a worse retry keeps the best
        #expect(a.data.days[StudyStore.day(.now)] == ["reading": 12])
        #expect(ReadingStore(file: url).data.best == ["a2-new-job": 2])
    }

    @Test func generatedPassagesPersistAndCanBeRemoved() {
        let url = TestData.file("reading.json")
        let s = ReadingStore(file: url)
        let p = Passage(id: "gen-1", level: "B1", title: "T", topic: "cloud", text: "t", questions: [], generated: true)
        s.add(p)
        s.finish("gen-1", score: 1)
        #expect(ReadingStore(file: url).all.last == p)
        s.remove("gen-1")
        let reloaded = ReadingStore(file: url)
        #expect(reloaded.data.generated.isEmpty && reloaded.data.best["gen-1"] == nil)
        #expect(reloaded.all.count == Library.readings.count)
    }

    @Test func readingXPEvent() { #expect(XPEvent.reading(ok: true).skill == .reading && XPEvent.reading(ok: false).xp == 2) }
}
