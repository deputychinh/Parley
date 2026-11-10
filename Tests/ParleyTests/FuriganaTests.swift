import Foundation
import Testing
@testable import Parley

/// PARLEY-22: kana readings above kanji.
@Suite struct FuriganaTests {
    private func r(_ text: String, _ reading: String? = nil) -> RubySegment { RubySegment(text: text, reading: reading) }

    @Test func readsKanjiWords() {
        #expect(Furigana.segments("今日は会議があります") == [r("今日", "きょう"), r("は"), r("会議", "かいぎ"), r("があります")])
    }

    @Test func keepsOkuriganaOutsideTheReading() {
        #expect(Furigana.split("始めましょう", reading: "はじめましょう") == [r("始", "はじ"), r("めましょう")])
        #expect(Furigana.split("お願い", reading: "おねがい") == [r("お"), r("願", "ねが"), r("い")])
        // a reading that does not end with the written kana → the whole word keeps the whole reading
        #expect(Furigana.split("行く", reading: "いった") == [r("行く", "いった")])
        #expect(Furigana.split("会議", reading: nil) == [r("会議")])
    }

    @Test func kanaLatinDigitsAndPunctuationGetNoReading() {
        #expect(Furigana.segments("カタカナとひらがな") == [r("カタカナとひらがな")])
        let mixed = Furigana.segments("Tokyo 2026、東京へ。")
        #expect(mixed.map(\.text).joined() == "Tokyo 2026、東京へ。") // nothing lost or doubled
        #expect(mixed.filter { $0.reading != nil } == [r("東京", "とうきょう")])
    }

    @Test func emptyAndConversionHelpers() {
        #expect(Furigana.segments("").isEmpty)
        #expect(Furigana.hiragana("kyou") == "きょう")
        #expect(Furigana.hiragana("kaigi") == "かいぎ")
        #expect(Furigana.hiragana(kana: "カタ") == "かた")
        #expect(Furigana.hiragana(kana: "abc") == nil)
        #expect(Furigana.isKanji("々") && !Furigana.isKanji("あ"))
    }

    @Test func mergesRunsWithoutReading() {
        #expect(Furigana.merge([r("あ"), r("い"), r("漢", "かん"), r("う")]) == [r("あい"), r("漢", "かん"), r("う")])
    }

    /// The pad prepares readings only for Japanese sources.
    @MainActor @Test func padAddsReadingsForJapaneseOnly() {
        let pad = TranslatePad()
        pad.input = "会議です"
        pad.translate(source: nil, target: Locale.Language(identifier: "vi"), supported: ["ja", "vi", "en"])
        #expect(pad.pairs.first?.ruby?.contains(r("会議", "かいぎ")) == true)
        let en = TranslatePad()
        en.input = "The meeting is today."
        en.translate(source: nil, target: Locale.Language(identifier: "vi"), supported: ["ja", "vi", "en"])
        #expect(en.pairs.first?.ruby == nil)
    }
}
