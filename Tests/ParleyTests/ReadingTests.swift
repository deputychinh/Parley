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
        var quiz = ReadingQuiz([ReadingQuestion(prompt: "1", options: ["a", "b", "c", "d"], answer: "a", explainVi: ""),
                                ReadingQuestion(prompt: "2", options: ["a", "b", "c", "d"], answer: "a", explainVi: "")])
        s.log(quiz.choose(0, "a"), passage: "a2-new-job")
        s.log(quiz.choose(1, "b"), passage: "a2-new-job")
        s.log(quiz.choose(1, "a"), passage: "a2-new-job") // already answered: nothing
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


/// PARLEY-6 review round 2: generation through an injectable writer, answers from the text, Vietnamese explanations.
@MainActor final class FakeWriter: PassageWriter {
    var drafts: [Result<DraftPassage, Error>]
    var calls = 0
    init(_ drafts: [Result<DraftPassage, Error>]) { self.drafts = drafts }
    func write(topic: String, level: CEFR) async throws -> DraftPassage {
        calls += 1
        return try drafts.removeFirst().get()
    }
}

@MainActor @Suite struct ReadingGenerationTests {
    let text = "Last week Lan visited a small farm near Da Lat. She picked strawberries in the morning and cooked lunch with the family. In the afternoon it rained, so everyone drank tea and talked about the harvest. Lan wants to visit again next spring with her friends from work. " + Array(repeating: "The farm was quiet and green.", count: 8).joined(separator: " ")
    func q(_ prompt: String, _ answer: String, _ others: [String]) -> ReadingQuestion {
        ReadingQuestion(prompt: prompt, options: [answer] + others, answer: answer, explainVi: "Đoạn 1 có câu trả lời.")
    }
    var good: DraftPassage {
        DraftPassage(title: "A farm visit", text: text, questions: [
            q("What did Lan pick?", "Strawberries", ["Apples", "Rice", "Flowers"]),
            q("What happened in the afternoon?", "It rained", ["It snowed", "It was hot", "Nothing"]),
            q("When does Lan want to come back?", "Next spring", ["Next winter", "Tomorrow", "Never"]),
        ])
    }

    @Test func goodDraftBecomesAPassage() async throws {
        let p = try await ReadingStore.generate(topic: "farm", level: .a2, writer: FakeWriter([.success(good)]))
        #expect(p.generated == true && p.questions.count == 3 && p.level == "A2" && p.topic == "farm")
    }

    @Test func answersNotInTheTextAreRejectedThenRetriedOnce() async throws {
        var bad = good
        bad.questions[0] = q("What did Lan cook?", "Fried rice with chicken", ["Soup", "Bread", "Noodles"]) // never said
        let writer = FakeWriter([.success(bad), .success(good)])
        let p = try await ReadingStore.generate(topic: "farm", level: .a2, writer: writer)
        #expect(writer.calls == 2 && p.questions.count == 3)
        let twice = FakeWriter([.success(bad), .success(bad)])
        await #expect(throws: Err.self) { try await ReadingStore.generate(topic: "farm", level: .a2, writer: twice) }
    }

    @Test func noRetryAfterATimeout() async {
        let writer = FakeWriter([.failure(TimeoutError(seconds: 60)), .success(good)])
        await #expect(throws: TimeoutError.self) { try await ReadingStore.generate(topic: "farm", level: .b1, writer: writer) }
        #expect(writer.calls == 1)
    }

    @Test func englishExplanationsAreDropped() throws {
        var d = good
        d.questions[0].explainVi = "The answer is in paragraph one."
        let p = try ReadingStore.build(d, topic: "farm", level: .a2, now: .now)
        #expect(p.questions[0].explainVi.isEmpty && !p.questions[1].explainVi.isEmpty)
    }

    @Test func supportedAnswers() {
        #expect(ReadingRules.supported("Strawberries", by: text))
        #expect(ReadingRules.supported("Six", by: "There are six people."))
        #expect(!ReadingRules.supported("Fried rice with chicken", by: text))
    }

    @Test func bundledExplanationsAreVietnamese() {
        for p in Library.readings { for q in p.questions { #expect(WritingRules.isVietnamese(q.explainVi), "\(p.id): \(q.prompt)") } }
    }
}


/// PARLEY-18: reading XP at most once per passage per day; the generator is off for v0.2.0.
@MainActor @Suite struct ReadingXPPerDayTests {
    let q = [ReadingQuestion(prompt: "1", options: ["a", "b", "c", "d"], answer: "a", explainVi: ""),
             ReadingQuestion(prompt: "2", options: ["a", "b", "c", "d"], answer: "a", explainVi: "")]

    @Test func reopeningAPassageTheSameDayEarnsNothing() {
        let a = ActivityStore(file: TestData.file("activity.json"))
        let url = TestData.file("reading.json")
        let s = ReadingStore(file: url, activity: a)
        s.beginVisit("p")
        var visit1 = ReadingQuiz(q)
        s.log(visit1.choose(0, "a"), passage: "p")
        s.log(visit1.choose(1, "a"), passage: "p")      // same visit: both questions count
        s.beginVisit("p")                                // leave and reopen
        var visit2 = ReadingQuiz(q)
        s.log(visit2.choose(0, "a"), passage: "p")
        let reloaded = ReadingStore(file: url, activity: a) // even after a restart
        reloaded.beginVisit("p")
        var visit3 = ReadingQuiz(q)
        reloaded.log(visit3.choose(0, "a"), passage: "p")
        #expect(a.data.days[StudyStore.day(.now)] == ["reading": 20])
        s.beginVisit("other")
        var other = ReadingQuiz(q)
        s.log(other.choose(0, "a"), passage: "other")   // another passage still counts
        #expect(a.data.days[StudyStore.day(.now)] == ["reading": 30])
    }

    @Test func tomorrowCountsAgain() {
        let a = ActivityStore(file: TestData.file("activity.json"))
        let s = ReadingStore(file: TestData.file("reading.json"), activity: a)
        let tomorrow = Date.now.addingTimeInterval(86_400)
        s.beginVisit("p")
        var v1 = ReadingQuiz(q)
        s.log(v1.choose(0, "a"), passage: "p")
        s.beginVisit("p", now: tomorrow)
        var v2 = ReadingQuiz(q)
        s.log(v2.choose(0, "a"), passage: "p", now: tomorrow)
        #expect(a.data.days[StudyStore.day(.now)] == ["reading": 10] && a.data.days[StudyStore.day(tomorrow)] == ["reading": 10])
    }

    @Test func generatorIsOffForThisRelease() {
        #expect(!ReadingStore.generatorEnabled && !ReadingStore.showsGenerator())
        #expect(ReadingStore.showsGenerator(enabled: true))
    }

    @Test func earnedTodayIsVisible() {
        let s = ReadingStore(file: TestData.file("reading.json"), activity: ActivityStore(file: TestData.file("a.json")))
        #expect(!s.earnedToday("p"))
        s.beginVisit("p")
        var v = ReadingQuiz(q)
        s.log(v.choose(0, "a"), passage: "p")
        #expect(s.earnedToday("p") && !s.earnedToday("p", now: .now.addingTimeInterval(86_400)))
    }
}
