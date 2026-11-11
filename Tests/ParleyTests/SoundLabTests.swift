import Foundation
import Testing
@testable import Parley

/// PARLEY-33: minimal pairs — hear, then say in a carrier; feedback names the sound.
@MainActor
struct SoundLabTests {
    @Test func everyPairWordIsInCMUdictAndSetsAreBigEnough() {
        for set in ContrastSet.all {
            #expect(set.items.count >= 6, "\(set.id)")
            for item in set.items {
                #expect((2...3).contains(item.count))
                for w in item { #expect(Pronunciation.phones(w) != nil, "\(w)") }
                // the words of an item really differ in sound
                #expect(Set(item.map { SoundDiff.bare(Pronunciation.phones($0) ?? []) }).count == item.count, "\(item)")
            }
            for id in set.sounds { #expect(IPASound.sound(id) != nil, "\(set.id): \(id)") }
        }
        #expect(ContrastSet.all.map(\.priority) == ContrastSet.all.map(\.priority).sorted()) // high first, θ/ð last
        #expect(ContrastSet.all.last?.id == "dh-d" && ContrastSet.all.first?.id == "finals")
    }

    @Test func slotIsTheWordsBetweenSaidAndAgain() {
        #expect(SoundDiff.slot(in: "I said ship again.") == "ship")
        #expect(SoundDiff.slot(in: "i SAID a bike again") == "a bike")
        #expect(SoundDiff.slot(in: "I said seed") == "seed")          // "again" lost
        #expect(SoundDiff.slot(in: "I said again.") == nil)
        #expect(SoundDiff.slot(in: "ship") == nil)
    }

    @Test func sameSoundsPassEvenWhenSpelledOtherwise() {
        #expect(SoundDiff.compare(target: "buy", said: "I said bye again.").same)      // homophones (spike: buy → "bye")
        #expect(SoundDiff.compare(target: "right", said: "I said write again.").same)
        #expect(SoundDiff.compare(target: "ship", said: "I said ship again.").same)
        #expect(SoundDiff.compare(target: "ship", said: "Ship.").same)                // the word alone is fine too
    }

    @Test func missesNameTheSound() {
        let sip = SoundDiff.compare(target: "ship", said: "I said sip again.")
        #expect(!sip.same && sip.heard == "sip" && sip.changes == [.swapped("SH", "S")])
        #expect(SoundDiff.describe(sip.changes) == "âm /ʃ/ thành /s/")
        #expect(SoundLabView.lesson(for: sip.changes)?.id == "SH")
        let see = SoundDiff.compare(target: "seat", said: "I said see again.")
        #expect(see.changes == [.missing("T")] && SoundDiff.describe(see.changes) == "thiếu âm /t/")
        let works = SoundDiff.compare(target: "work", said: "I said works again.")
        #expect(works.changes == [.extra("S")] && SoundDiff.describe(works.changes) == "thừa âm /s/")
        #expect(SoundLabView.lesson(for: works.changes) == nil)
        let sheep = SoundDiff.compare(target: "sheep", said: "I said ship again.")
        #expect(sheep.changes == [.swapped("IY", "IH")] && SoundDiff.describe(sheep.changes) == "âm /i/ thành /ɪ/")
    }

    @Test func sayOnlyWordsTheRecognizerKeeps() {
        for set in ContrastSet.all {
            #expect(set.sayable.count >= LabRound.length / 2, "\(set.id)")
            #expect(Set(set.sayable).isDisjoint(with: ContrastSet.hearOnly))
        }
        for w in ContrastSet.hearOnly { #expect(ContrastSet.all.contains { $0.words.contains(w) }, "\(w)") } // still heard
        var rng = SeededRNG(seed: 3)
        let round = LabRound.make(ContrastSet.set("dh-d")!, voices: 2, using: &rng)
        #expect(Set(round.say).isDisjoint(with: ContrastSet.hearOnly))
    }

    @Test func digitsAreWords() {
        #expect(SoundDiff.compare(target: "nine", said: "I said 9 again.").same)
        #expect(SoundDiff.compare(target: "three", said: "I said 3 again.").same)
        #expect(SoundDiff.compare(target: "tree", said: "I said 3 again.").changes == [.swapped("T", "TH")])
    }

    @Test func hintsAreTheWholePair() {
        let set = ContrastSet.set("dh-d")!
        #expect(set.context(for: "den") == ["then", "I said then again.", "den", "I said den again."])
        #expect(set.context(for: "nothing-here") == ["nothing-here", "I said nothing-here again."])
    }

    @Test func noCarrierMeansSayItAgain() {
        let r = SoundDiff.compare(target: "ship", said: "the weather is nice")
        #expect(r.heard == nil && !r.same)
        #expect(SoundDiff.compare(target: "ship", said: "").heard == nil)
        #expect(ContrastSet.carrier("ship") == "I said ship again.")
    }

    @Test func roundsRotateVoicesAndCoverTheSet() {
        var rng = SeededRNG(seed: 7)
        let set = ContrastSet.set("s-sh")!
        let round = LabRound.make(set, voices: 3, using: &rng)
        #expect(round.hear.count == LabRound.length && round.say.count == LabRound.length)
        #expect(round.hear.map(\.voice) == [0, 1, 2, 0, 1, 2, 0, 1, 2, 0])
        for t in round.hear { #expect(t.options.contains(t.target) && set.items.contains(t.options)) }
        #expect(Set(round.say).isSubset(of: Set(set.sayable)) && Set(round.say).count == LabRound.length)
        #expect(LabRound.make(set, voices: 0, using: &rng).hear.allSatisfy { $0.voice == 0 }) // no voices installed
    }

    @Test func storeKeepsResultsAndLogsXP() {
        let activity = ActivityStore(file: TestData.file("activity.json"))
        let url = TestData.file("sounds.json")
        let store = SoundStore(file: url, activity: activity)
        #expect(store.next?.id == "finals")
        for i in 0..<10 { store.record("finals", saying: true, right: i < 8) }
        store.record("finals", saying: false, right: true)
        store.record("finals", saying: false, right: false)
        let s = store.stats["finals"]!
        #expect(s.said == 10 && s.saidRight == 8 && s.heard == 2 && s.heardRight == 1 && s.passed)
        #expect(s.last == StudyStore.day(.now))
        #expect(store.next?.id == "endings") // passed sets are skipped
        let today = StudyStore.day(.now)
        #expect(activity.data.days[today]?["speaking"] == 8 * 10 + 2 * 2 && activity.data.days[today]?["listening"] == 10 + 2)
        #expect(SoundStore(file: url).stats == store.stats) // saved
        #expect(!SoundStats(said: 9, saidRight: 9).passed && !SoundStats(said: 10, saidRight: 7).passed)
    }
}

/// Deterministic randomness for tests (SplitMix64).
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
