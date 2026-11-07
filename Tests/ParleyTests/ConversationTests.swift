import AppKit
import Foundation
import FoundationModels
import Testing
@testable import Parley

/// PARLEY-4: the deterministic parts of the conversation coach (spec S4). Model quality is `make ai-eval`.
@Suite struct CoachTests {
    @Test func scenarioCatalog() {
        let ids = Scenario.all.map(\.id)
        #expect(Scenario.all.count >= 8 && Set(ids).count == ids.count)
        for id in ["standup", "interview", "restaurant", "hotel", "smalltalk", "deadline", "support", "doctor"] {
            #expect(ids.contains(id), "AC4.1 scenario \(id)")
        }
        #expect(Scenario.all.allSatisfy { !$0.opener.isEmpty && $0.role.hasPrefix("You are") && !$0.goal.isEmpty })
        #expect(Scenario.all.allSatisfy { NSImage(systemSymbolName: $0.symbol, accessibilityDescription: nil) != nil })
    }

    @Test func instructionsCarryRoleAndLevel() {
        let s = Scenario.all[0]
        let text = Coach.instructions(s, .a2)
        #expect(text.contains(s.role) && text.contains("A2") && text.contains("Vietnamese"))
        #expect(Coach.instructions(s, .c1).contains("C1"))
    }

    @Test func cleanTrimsAndCaps() {
        #expect(Coach.clean("  hi there \n") == "hi there")
        #expect(Coach.clean("   \n ") == nil)
        #expect(Coach.clean(String(repeating: "a", count: 1_000))?.count == Coach.maxInput)
    }

    @Test(arguments: [
        ("Yesterday I fix the bug.", "Yesterday I fixed the bug.", true),
        ("I fixed the bug.", "I fixed the bug.", false),
        ("i fixed the bug", "I fixed the bug.", false),      // case + punctuation only
        ("lets go", "Let's go.", false),                       // apostrophe only
        ("I fixed the bug.", "", false),                       // model returned nothing
        ("I fixed the bug.", "   ", false),
    ])
    func correctionOnlyWhenWordsDiffer(original: String, corrected: String, expected: Bool) {
        #expect(Coach.hasMistake(original: original, corrected: corrected) == expected)
    }

    @Test func naturalPhrasingOnlyWhenNew() {
        #expect(!Coach.showsNatural(original: "I fixed it", corrected: "I fix it", natural: "I fixed it.")) // same as what was said
        #expect(!Coach.showsNatural(original: "I fix login bug yesterday", corrected: "I fixed the login bug yesterday",
                                    natural: "Great job, keep going!"))                                      // a compliment, not a rewrite
        #expect(!Coach.showsNatural(original: "Yesterday I fix the login bug and write some test",
                                    corrected: "Yesterday I fixed the login bug and wrote some tests",
                                    natural: "You fixed the login bug and wrote some tests — good job!"))   // praise that overlaps (seen in a review)
        #expect(Coach.isPraise("Well done!") && !Coach.isPraise("I sorted out the login bug yesterday"))
        #expect(Coach.showsNatural(original: "I fix bug.", corrected: "I fixed the bug.", natural: "I sorted out the bug."))
        #expect(!Coach.showsNatural(original: "I fix bug.", corrected: "I fixed the bug.", natural: "I fixed the bug"))
        #expect(!Coach.showsNatural(original: "I fixed the bug.", corrected: "I fixed the bug.", natural: "i fixed the bug"))
        #expect(!Coach.showsNatural(original: "a", corrected: "a", natural: " "))
    }

    @Test func evalSetCoversMistakesAndCorrectSentences() {
        #expect(AIEval.cases.count >= 8)
        #expect(AIEval.cases.contains { $0.mustContain == nil } && AIEval.cases.contains { $0.mustContain != nil })
    }

    @Test func xpForATurn() { #expect(XP.turn == 15) }
}


/// `ConversationModel` with a fake engine: send, XP, errors, saving phrases, screen choice (spec S4).
@MainActor final class FakeCoach: CoachEngine {
    var replies: [Result<CoachReply, Error>]
    var seen: [(String, String)] = []
    init(_ replies: [Result<CoachReply, Error>]) { self.replies = replies }
    func turn(after ai: String, learner: String) async throws -> CoachReply {
        seen.append((ai, learner))
        return try replies.removeFirst().get()
    }
}

@MainActor @Suite struct ConversationModelTests {
    let s = Scenario.all[0]
    func reply(_ text: String, corrected: String, natural: String = "", tip: String = "Mẹo") -> Result<CoachReply, Error> {
        .success(CoachReply(reply: text, corrected: corrected, natural: natural, tipVi: tip))
    }

    @Test func turnsAddFeedbackAndXPByInputKind() async {
        let a = ActivityStore(file: TestData.file("activity.json"))
        let fake = FakeCoach([reply("Nice. Anything else?", corrected: "Yesterday I fixed the bug.", natural: "I sorted out the bug yesterday."),
                              reply("Great!", corrected: "Today I will test it.")])
        let m = ConversationModel(scenario: s, level: .b1, activity: a, engine: fake)
        #expect(await m.send("  Yesterday I fix the bug. ", spoken: true) == "Nice. Anything else?")
        #expect(await m.send("Today I will test it.", spoken: false) == "Great!")
        #expect(fake.seen.map(\.0) == [s.opener, "Nice. Anything else?"])          // AI line the learner answered
        #expect(m.lines.map(\.who) == [.ai, .learner, .ai, .learner, .ai])
        #expect(m.lines[1].text == "Yesterday I fix the bug." && m.lines[1].corrected == "Yesterday I fixed the bug.")
        #expect(m.lines[1].natural == "I sorted out the bug yesterday." && m.lines[1].tip == "Mẹo")
        #expect(m.lines[3].corrected == nil)                                         // correct sentence: no correction
        #expect(m.learnerTurns == 2 && m.corrections.count == 1)
        #expect(a.data.days[StudyStore.day(.now)] == ["speaking": 15, "writing": 15])
    }

    @Test func modelErrorRemovesTheTurnAndEarnsNothing() async {
        struct Boom: LocalizedError { var errorDescription: String? { "boom" } }
        let a = ActivityStore(file: TestData.file("activity.json"))
        let m = ConversationModel(scenario: s, level: .b1, activity: a, engine: FakeCoach([.failure(Boom())]))
        #expect(await m.send("Hello there", spoken: false) == nil)
        #expect(m.lines.count == 1 && m.error == ModelCoach.message(for: Boom()) && !m.thinking)
        #expect(m.error?.contains("boom") == false)                     // Vietnamese only, no system text
        #expect(m.consumeDraft() == "Hello there" && m.consumeDraft() == nil) // the learner's words come back once
        #expect(a.data.days.isEmpty)
    }

    @Test func contextWindowHasItsOwnMessage() {
        let e = LanguageModelSession.GenerationError.exceededContextWindowSize(.init(debugDescription: "full"))
        #expect(ModelCoach.message(for: e).contains("quá dài"))
    }

    @Test func endingDropsAReplyStillOnItsWay() async {
        let a = ActivityStore(file: TestData.file("activity.json"))
        final class EndingCoach: CoachEngine {
            weak var model: ConversationModel?
            func turn(after ai: String, learner: String) async throws -> CoachReply {
                model?.end() // the learner presses "Kết thúc" while the model is thinking
                return CoachReply(reply: "Late reply", corrected: learner, natural: "", tipVi: "")
            }
        }
        let coach = EndingCoach()
        let m = ConversationModel(scenario: s, level: .b1, activity: a, engine: coach)
        coach.model = m
        #expect(await m.send("Hello", spoken: true) == nil)
        #expect(m.lines.count == 1 && m.error == nil && m.consumeDraft() == nil && a.data.days.isEmpty)
        #expect(await m.send("Again", spoken: false) == nil) // nothing is sent after the end
    }

    @Test func emptyInputIsNotSentAndEmptyReplyGetsAFallback() async {
        let fake = FakeCoach([reply("   ", corrected: "Hi.")])
        let m = ConversationModel(scenario: s, level: .b1, engine: fake)
        #expect(await m.send("   ", spoken: false) == nil && fake.seen.isEmpty)
        #expect(await m.send("Hi.", spoken: false) == "Sorry, could you say that again?")
    }

    @Test func savingAPhraseAddsItOnce() async {
        let vocab = VocabStore(file: TestData.file("vocabulary.json"))
        let m = ConversationModel(scenario: s, level: .b1, engine: FakeCoach([]))
        #expect(await m.save("sort out", to: vocab) { _ in "giải quyết" })
        #expect(await m.save("Sort out", to: vocab) { _ in "x" } == false)
        #expect(vocab.items.map(\.term) == ["sort out"] && vocab.items[0].meaning == "giải quyết")
    }

    @Test func screenChoice() {
        #expect(ConversationScreen.pick(available: false, active: true) == .unavailable) // AC4.5
        #expect(ConversationScreen.pick(available: true, active: false) == .picker)
        #expect(ConversationScreen.pick(available: true, active: true) == .session)
    }
}


/// PARLEY-14 review round 1: praise list without false positives, the shared main-actor timeout.
@MainActor @Suite struct CoachRound2Tests {
    @Test func realRewritesWithPraiseWordsAreKept() {
        #expect(!Coach.isPraise("The service is excellent now"))
        #expect(!Coach.isPraise("It was the perfect time to deploy"))
        #expect(!Coach.isPraise("You did the review yesterday"))
        #expect(Coach.isPraise("Nice job on the fix!") && Coach.isPraise("You did well."))
    }

    @Test func mainActorTimeoutFailsSlowWorkAndPassesFastWork() async throws {
        await #expect(throws: TimeoutError.self) { try await modelTimeout(0.05) { try await Task.sleep(for: .seconds(5)); return 1 } }
        #expect(try await modelTimeout(1) { 7 } == 7)
        #expect(ModelCoach.timeout == 30)
    }
}


/// PARLEY-14 review round 2: the timeout inside the real engine, caller cancellation, first-person sentences.
@MainActor @Suite struct ModelCoachTimeoutTests {
    @Test func turnTimesOutWithItsOwnError() async {
        let slow = ModelCoach(instructions: "x", timeout: 0.05) { _ in
            try await Task.sleep(for: .seconds(5))
            return CoachReply(reply: "late", corrected: "", natural: "", tipVi: "")
        }
        await #expect(throws: TimeoutError.self) { try await slow.turn(after: "Hi", learner: "Hello") }
        #expect(ModelCoach.message(for: TimeoutError(seconds: 30)).contains("30 giây"))
    }

    @Test func fastResponderPassesThrough() async throws {
        let fast = ModelCoach(instructions: "x", timeout: 1) { prompt in CoachReply(reply: prompt, corrected: "", natural: "", tipVi: "") }
        #expect(try await fast.turn(after: "Hi", learner: "Hello").reply.contains("Learner: \"Hello\""))
    }

    @Test func callerCancellationIsNotATimeout() async {
        let t = Task { @MainActor in try await modelTimeout(5) { try await Task.sleep(for: .seconds(5)); return 1 } }
        try? await Task.sleep(for: .milliseconds(50))
        t.cancel()
        await #expect(throws: CancellationError.self) { try await t.value }
    }

    @Test func firstPersonSentencesAreNotPraise() {
        #expect(!Coach.isPraise("I did a good job on the release"))
        #expect(Coach.isPraise("Good job on the release!"))
    }
}


/// PARLEY-17: the timeout returns on time even when the work ignores cancellation; the session is reset.
@MainActor @Suite struct ModelTimeoutTests {
    @Test func workThatIgnoresCancellationStillTimesOutOnTime() async {
        let clock = ContinuousClock()
        let start = clock.now
        await #expect(throws: TimeoutError.self) {
            try await modelTimeout(0.1) { () async throws -> Int in
                let until = ContinuousClock.now + .seconds(2)
                while ContinuousClock.now < until { try? await Task.sleep(for: .milliseconds(20)) } // swallows cancellation
                return 1
            }
        }
        #expect(clock.now - start < .seconds(1)) // did not wait the 2 s
    }

    @Test func coachResetsItsSessionAfterATimeout() async {
        let slow = ModelCoach(instructions: "x", timeout: 0.05) { _ in
            try? await Task.sleep(for: .seconds(2))
            return CoachReply(reply: "late", corrected: "", natural: "", tipVi: "")
        }
        _ = try? await slow.turn(after: "Hi", learner: "Hello")
        #expect(slow.sessionResets == 1)
    }
}
