import Foundation
import SwiftUI
import Testing
@testable import Parley

/// PARLEY-22: kana readings above kanji.
@Suite struct FuriganaTests {
    private func r(_ text: String, _ reading: String? = nil) -> RubySegment { RubySegment(text: text, reading: reading) }

    @Test func readsKanjiWords() {
        let s = Furigana.segments("今日は会議があります")
        #expect(s.map(\.text).joined() == "今日は会議があります")
        #expect(s.filter { $0.reading != nil } == [r("今日", "きょう"), r("会議", "かいぎ")])
        #expect(s.count > 3) // word-sized pieces, so long text can wrap between words
    }

    @Test func keepsOkuriganaOutsideTheReading() {
        #expect(Furigana.split("始めましょう", reading: "はじめましょう") == [r("始", "はじ"), r("めましょう")])
        #expect(Furigana.split("お願い", reading: "おねがい") == [r("お"), r("願", "ねが"), r("い")])
        // a reading that does not end with the written kana → the whole word keeps the whole reading
        #expect(Furigana.split("行く", reading: "いった") == [r("行く", "いった")])
        #expect(Furigana.split("会議", reading: nil) == [r("会議")])
    }

    @Test func kanaLatinDigitsAndPunctuationGetNoReading() {
        #expect(Furigana.segments("カタカナとひらがな").allSatisfy { $0.reading == nil })
        let mixed = Furigana.segments("Tokyo 2026、東京へ。")
        #expect(mixed.map(\.text).joined() == "Tokyo 2026、東京へ。") // nothing lost or doubled
        #expect(mixed.filter { $0.reading != nil } == [r("東京", "とうきょう")])
    }

    /// Counters after digits are read differently (14日 = じゅうよっか): no guess rather than a wrong one.
    @Test func noReadingRightAfterADigit() {
        let date = Furigana.segments("3月14日に会議")
        #expect(date.map(\.text).joined() == "3月14日に会議")
        #expect(date.filter { $0.reading != nil } == [r("会議", "かいぎ")])
        #expect(Furigana.segments("３日").allSatisfy { $0.reading == nil }) // full-width digit
        let people = Furigana.segments("2人で行きます") // the tokenizer keeps 2人 as one token
        #expect(people.map(\.text).joined() == "2人で行きます")
        #expect(people.compactMap(\.reading).allSatisfy(Furigana.isHiragana))
        #expect(people.first { $0.text.contains("人") }?.reading == nil)
    }

    @Test func kanjiBeyondTheBasicPlane() {
        #expect(Furigana.isKanji("𠮷") && Furigana.isKanji("々") && !Furigana.isKanji("あ") && !Furigana.isKanji("A"))
    }

    @Test func emptyAndConversionHelpers() {
        #expect(Furigana.segments("").isEmpty)
        #expect(Furigana.hiragana("kyou") == "きょう")
        #expect(Furigana.hiragana("kaigi") == "かいぎ")
        #expect(Furigana.hiragana(kana: "カタ") == "かた")
        #expect(Furigana.hiragana(kana: "abc") == nil)
        #expect(Furigana.hiragana("2ren") == nil) // digit and accent left over
        #expect(Furigana.isHiragana("きょー") && !Furigana.isHiragana("") && !Furigana.isHiragana("れ́"))
    }

    @Test func longRunsWithoutReadingAreCutSoTheyWrap() {
        let url = String(repeating: "a", count: 20)
        #expect(Furigana.pieces([r(url), r("漢字", "かんじ"), r("です")]) == url.map { r(String($0)) } + [r("漢字", "かんじ"), r("です")])
    }

    @Test func wrapsGreedily() {
        let sizes = [CGSize(width: 40, height: 20), CGSize(width: 40, height: 30), CGSize(width: 40, height: 20), CGSize(width: 200, height: 20)]
        let rows = WrapLayout.rows(width: 100, sizes: sizes)
        #expect(rows.map(\.items) == [[0, 1], [2], [3]]) // a too-wide item gets its own line
        #expect(rows[0].height == 30 && rows[0].width == 80)
    }

    /// Readings are prepared off the main actor, only for Japanese, and only up to `Furigana.limit` characters.
    @MainActor @Test func padAddsReadingsForShortJapaneseOnly() async {
        let vi = Locale.Language(identifier: "vi"), all: Set<String> = ["ja", "vi", "en"]
        let pad = TranslatePad()
        pad.input = "会議です"
        pad.translate(source: nil, target: vi, supported: all)
        await pad.readingsTask?.value
        #expect(pad.hasReadings && pad.pairs.first?.ruby?.contains(r("会議", "かいぎ")) == true)

        let en = TranslatePad()
        en.input = "The meeting is today."
        en.translate(source: nil, target: vi, supported: all)
        await en.readingsTask?.value
        #expect(!en.hasReadings && !en.readingsSkipped)

        let long = TranslatePad()
        long.input = String(repeating: "会議です。", count: Furigana.limit / 5 + 1)
        long.translate(source: Locale.Language(identifier: "ja"), target: vi, supported: all)
        await long.readingsTask?.value
        #expect(!long.hasReadings && long.readingsSkipped)
    }

    @MainActor @Test func clearDropsReadingsInFlight() async {
        let pad = TranslatePad()
        pad.input = "会議です"
        pad.translate(source: nil, target: Locale.Language(identifier: "vi"), supported: ["ja", "vi"])
        let task = pad.readingsTask
        pad.clear()
        await task?.value
        #expect(pad.pairs.isEmpty && !pad.hasReadings)
    }

    /// A slow readings task of an older request never writes over a newer text with as many paragraphs.
    @MainActor @Test func staleReadingsAreIgnored() {
        let vi = Locale.Language(identifier: "vi")
        let pad = TranslatePad()
        pad.input = "会議です"
        pad.translate(source: nil, target: vi, supported: ["ja", "vi"])
        let older = pad.generation
        pad.clear()
        pad.input = "資料です"
        pad.translate(source: nil, target: vi, supported: ["ja", "vi"])
        #expect(!pad.applyReadings([[r("会議", "かいぎ"), r("です")]], for: older))
        #expect(pad.pairs[0].ruby?.contains(r("会議", "かいぎ")) != true)
        #expect(pad.applyReadings([[r("資料", "しりょう"), r("です")]], for: pad.generation))
        #expect(pad.pairs[0].ruby?.first == r("資料", "しりょう"))
        #expect(!pad.applyReadings([], for: pad.generation)) // wrong paragraph count
    }

    /// The "Cách đọc" toggle decides what is drawn.
    @Test func toggleChoosesReadingsOrPlainText() {
        let pair = TranslatePad.Pair(id: 0, source: "会議", ruby: [r("会議", "かいぎ")])
        #expect(TranslatePad.shownReading(pair, enabled: true) == [r("会議", "かいぎ")])
        #expect(TranslatePad.shownReading(pair, enabled: false) == nil)
        #expect(TranslatePad.shownReading(TranslatePad.Pair(id: 1, source: "Hi"), enabled: true) == nil)
    }
}

/// W4: the most text that gets readings (`Furigana.limit`) is segmented and laid out without stalling the window.
@Suite struct BenchFurigana {
    static let text = String(String(repeating: "来週の会議は火曜日の午後二時からです。資料は前日までに共有してください。", count: 60).prefix(Furigana.limit))

    @Test func segmentsAtTheLimit() {
        let clock = ContinuousClock()
        let elapsed = (0..<3).map { _ in clock.measure { _ = Furigana.segments(Self.text) } }.min()!
        print("BenchFuriganaSegments: \(elapsed)")
        #expect(elapsed < .milliseconds(100))
    }

    /// Main-actor layout: only in `make bench` (PARLEY_BENCH=1), so it never starves main-actor timing tests in `make test`.
    @MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["PARLEY_BENCH"] != nil))
    func layoutAtTheLimit() {
        let segments = Furigana.segments(Self.text)
        let clock = ContinuousClock()
        let elapsed = (0..<3).map { _ in
            clock.measure {
                let renderer = ImageRenderer(content: RubyText(segments: segments).frame(width: 600))
                _ = renderer.cgImage
            }
        }.min()!
        print("BenchFuriganaLayout: \(elapsed)")
        #expect(elapsed < .milliseconds(400))
    }
}
