import Foundation
import Testing
@testable import Parley

/// PARLEY-32: the IPA chart teaches every sound CMUdict writes, with examples that really contain it.
struct SoundsTests {
    @Test func everyExampleContainsItsSound() {
        for sound in IPASound.all {
            #expect(sound.examples.count >= 4, "\(sound.id)")
            for word in sound.examples {
                let phones = Pronunciation.phones(word)
                #expect(phones != nil, "\(word) not in CMUdict")
                #expect(phones?.contains(where: sound.matches) == true, "\(word) has no /\(sound.symbol)/")
            }
        }
    }

    @Test func chartCoversEveryCMUdictSoundOnce() {
        // Every symbol `Pronunciation.ipa` can write belongs to exactly one sound on the chart.
        let phones = ["AA", "AE", "AH", "AO", "AW", "AY", "B", "CH", "D", "DH", "EH", "ER", "EY", "F", "G", "HH", "IH", "IY",
                      "JH", "K", "L", "M", "N", "NG", "OW", "OY", "P", "R", "S", "SH", "T", "TH", "UH", "UW", "V", "W", "Y",
                      "Z", "ZH"]
        for base in phones {
            for phone in base.first.map({ "AEIOU".contains($0) }) == true ? [base + "0", base + "1", base + "2"] : [base] {
                #expect(IPASound.all.count(where: { $0.matches(phone) }) == 1, "\(phone)")
            }
        }
        #expect(Set(IPASound.all.map(\.id)).count == IPASound.all.count)
        #expect(IPASound.sound("AH0")?.symbol == "ə" && IPASound.sound("ER0")?.symbol == "ɚ")
        #expect(IPASound.sound("SH")?.symbol == "ʃ" && IPASound.sound("IY")?.symbol == "i" && IPASound.sound("AH")?.symbol == "ʌ")
    }

    @Test func examplesShowWhereTheSoundSits() {
        // Consonants that English allows anywhere: an example at the start, in the middle and at the end.
        let limited: [String: Set<String>] = ["HH": ["start", "middle"], "W": ["start", "middle"], "Y": ["start", "middle"],
                                              "NG": ["middle", "end"], "ZH": ["middle"]]
        for sound in IPASound.all where !"AEIOU".contains(sound.id.first!) {
            let seen = sound.examples.reduce(into: Set<String>()) { $0.formUnion(sound.positions(in: $1)) }
            #expect(seen.isSuperset(of: limited[sound.id] ?? ["start", "middle", "end"]), "\(sound.id): \(seen)")
        }
        #expect(IPASound.sound("S")?.positions(in: "basic") == ["middle"])
    }

    @Test func pairsSitSideBySide() {
        let pairs = IPASound.pairs(IPASound.all.filter { $0.group == .pair })
        #expect(pairs.map { "\($0.0.id)/\($0.1.id)" } == ["P/B", "T/D", "K/G", "F/V", "TH/DH", "S/Z", "SH/ZH", "CH/JH"])
    }

    @Test func prioritiesFollowTheMethod() {
        // brief.md: finals, -s/-ed, vowel length, s–ʃ first; θ/ð last.
        for id in ["P", "B", "T", "D", "K", "G", "S", "Z", "V", "F", "L", "SH", "IY", "IH"] { #expect(IPASound.sound(id)?.priority == .high, "\(id)") }
        for id in ["TH", "DH"] { #expect(IPASound.sound(id)?.priority == .low, "\(id)") }
    }

    @Test func lessonHighlightsOnlyTheSound() {
        let ship = SoundLesson.highlighted("ship", IPASound.sound("SH")!)
        #expect(String(ship.characters) == "/ʃɪp/")
        let bold = ship.runs.filter { $0.foregroundColor == .parley }.map { String(ship[$0.range].characters) }
        #expect(bold == ["ʃ"])
        #expect(Pronunciation.phones("Ship") == ["SH", "IH1", "P"] && Pronunciation.phones("qwzx") == nil)
    }
}
