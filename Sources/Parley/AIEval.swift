import Foundation

// MARK: - `make ai-eval`

/// Known learner sentences → does the on-device coach fix the planted mistake and leave correct sentences alone?
enum AIEval {
    struct Case { let text: String; let mustContain: String? } // nil = sentence is correct, expect no correction

    static let cases: [Case] = [
        Case(text: "Yesterday I fix the login bug and write some tests.", mustContain: "fixed"),
        Case(text: "She don't agree with the new deadline.", mustContain: "doesn't"),
        Case(text: "I have finished the report yesterday.", mustContain: "finished the report yesterday"),
        Case(text: "We discussed about the budget in the meeting.", mustContain: "discussed the budget"),
        Case(text: "Can you explain me how the cache works?", mustContain: "explain to me"),
        Case(text: "I am working here since 2020.", mustContain: "have been working"),
        Case(text: "I finished the API yesterday and today I will write the tests.", mustContain: nil),
        Case(text: "Could we move the release to next Tuesday?", mustContain: nil),
    ]

    /// Prints one line per case plus hit rate and p50 latency; true when ≥ 60 % (ADR 0001) and p50 < 8 s (spec).
    @MainActor static func run() async -> Bool {
        guard ExampleWriter.available else { print("ai-eval: Apple Intelligence not available"); return false }
        var hits = 0
        var times: [Double] = []
        for c in cases {
            let engine = ModelCoach(instructions: Coach.instructions(Scenario.all[0], .b1))
            let t0 = Date()
            let turn: CoachReply?
            do { turn = try await engine.turn(after: "What did you work on yesterday?", learner: c.text) } catch {
                print("  model error:", error)
                turn = nil
            }
            times.append(Date().timeIntervalSince(t0))
            let corrected = turn?.corrected ?? ""
            let fixed = Coach.hasMistake(original: c.text, corrected: corrected)
            let ok = c.mustContain.map { fixed && corrected.lowercased().contains($0) } ?? !fixed
            if ok { hits += 1 }
            print(String(format: "  %@ %.1fs  %@ → %@", ok ? "✔" : "✘", times.last!, c.text, corrected))
        }
        let p50 = times.sorted()[times.count / 2]
        let rate = Double(hits) / Double(cases.count)
        print(String(format: "ai-eval conversation: %d/%d (%.0f%%), p50 %.1fs", hits, cases.count, rate * 100, p50))
        return rate >= 0.6 && p50 < 8
    }

    /// A paragraph with 6 planted mistakes: the coach must find at least 2 and finish in < 20 s. Measured runs vary
    /// between 2 and 4 found (small on-device model); the gate guards against a broken prompt, not for perfection.
    static let essay = "Last week our team have released the new payment page. Before the release we was very busy, "
        + "because the tests was failing every day. I fixed many bugs and I learn a lot about the code. "
        + "Now the page is more faster and the customers is happy."
    static let planted = ["have released", "we was", "tests was", "I learn", "more faster", "customers is"]

    @MainActor static func runWriting() async -> Bool {
        guard ExampleWriter.available else { return false }
        let t0 = Date()
        guard let entry = try? await WritingStore.review(essay, prompt: "Write a short status update.") else {
            print("ai-eval writing: model error")
            return false
        }
        let seconds = Date().timeIntervalSince(t0)
        let found = planted.filter { p in
            entry.mistakes.contains { $0.original.lowercased().contains(p.lowercased()) || p.lowercased().contains($0.original.lowercased()) }
        }
        print(String(format: "ai-eval writing: %d/%d planted mistakes found, %d reported, level %@, %.1fs",
                     found.count, planted.count, entry.mistakes.count, entry.level, seconds))
        for m in entry.mistakes { print("  \(m.original) → \(m.fix) — \(m.explanation)") }
        return found.count >= 2 && seconds < 20
    }
}
