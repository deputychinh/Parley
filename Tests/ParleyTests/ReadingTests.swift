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
        var p = Passage(id: "x", level: "B1", title: "T", topic: "t", text: text, questions: [q, q, q])
        #expect(ReadingRules.problem(with: p) == nil)
        p.questions = [q, q]                                            // AC6.3: exactly 3
        #expect(ReadingRules.problem(with: p)?.contains("câu hỏi") == true)
        p.questions = [q, q, q]; p.text = "too short"
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


/// PARLEY-6 review round 1: XP once per question per visit, option order, generation rules.
@Suite struct ReadingQuizTests {
    let qs = [ReadingQuestion(prompt: "1", options: ["a", "b", "c", "d"], answer: "a", explainVi: ""),
              ReadingQuestion(prompt: "2", options: ["a", "b", "c", "d"], answer: "b", explainVi: "")]

    @Test func retryEarnsNoXP() {
        var quiz = ReadingQuiz(qs)
        #expect(quiz.choose(0, "a") == .reading(ok: true))
        #expect(quiz.choose(0, "b") == nil)              // already answered
        #expect(quiz.choose(1, "c") == .reading(ok: false))
        #expect(quiz.finished && quiz.score == 1)
        quiz.retry()
        #expect(!quiz.finished && quiz.choose(0, "a") == nil && quiz.choose(1, "b") == nil) // no XP farming
        #expect(quiz.finished && quiz.score == 2)
        #expect(quiz.choose(5, "a") == nil)
    }

    @Test func optionOrderIsStableAndAPermutation() {
        let q = ReadingQuestion(prompt: "?", options: ["short", "a much longer right answer", "mid size", "tiny"], answer: "a much longer right answer", explainVi: "")
        let a = ReadingRules.displayOrder(q, seed: "p1")
        #expect(a == ReadingRules.displayOrder(q, seed: "p1") && Set(a) == Set(q.options))
        let firstPositions = Set((0..<12).map { ReadingRules.displayOrder(q, seed: "p\($0)").firstIndex(of: q.answer)! })
        #expect(firstPositions.count > 1)                // the answer does not always land in the same place
    }

    @Test func generationRules() {
        #expect(ReadingRules.wordTarget(.a2) == 100...150 && ReadingRules.wordTarget(.c1).lowerBound >= 180)
        #expect(ReadingRules.vietnameseOrEmpty("The answer is in paragraph 2.") == "")
        #expect(ReadingRules.vietnameseOrEmpty("Đoạn 2 có câu trả lời.") == "Đoạn 2 có câu trả lời.")
        #expect(!Library.readings.contains { $0.text.contains("colour") || $0.text.contains("Organisation") })
    }

    @Test func interpreterToolbarOnlyWhereItBelongs() {
        #expect(Route.showsInterpreter(.live, running: false))
        #expect(Route.showsInterpreter(.session(URL(fileURLWithPath: "/x.md")), running: false))
        #expect(!Route.showsInterpreter(.reading, running: false) && !Route.showsInterpreter(.conversation, running: false))
        #expect(Route.showsInterpreter(.reading, running: true)) // a running session can always be stopped
    }
}
