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

    @Test func prioritiesFollowTheMethod() {
        // brief.md: finals, -s/-ed, vowel length, s–ʃ first; θ/ð last.
        for id in ["T", "D", "K", "S", "Z", "V", "F", "L", "SH", "IY", "IH"] { #expect(IPASound.sound(id)?.priority == .high, "\(id)") }
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
