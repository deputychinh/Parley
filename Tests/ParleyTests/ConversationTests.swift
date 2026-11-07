import AppKit
import Foundation
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
