import AppKit
import Foundation
import Testing
@testable import Parley

/// PARLEY-21: text preparation, language detection, OCR line joining and the translate pad's states.
@Suite struct TextTranslationTests {
    @Test func preparesParagraphs() {
        #expect(TextTranslation.prepare("  \n ") == PreparedText(paragraphs: [], truncated: false))
        #expect(TextTranslation.prepare(" 一行目。\r\n\n  二行目。 \n") == PreparedText(paragraphs: ["一行目。", "二行目。"], truncated: false))
    }

    @Test func cutsAtTheLimit() {
        let exact = String(repeating: "あ", count: TextTranslation.limit)
        #expect(TextTranslation.prepare(exact) == PreparedText(paragraphs: [exact], truncated: false))
        let over = TextTranslation.prepare(exact + "い")
        #expect(over.truncated && over.paragraphs == [exact])
    }

    @Test func detectsLanguages() {
        let all: Set<String> = ["ja", "zh", "en", "vi", "ko"]
        #expect(TextTranslation.detect("今日は会議があります", among: all)?.languageCode == .japanese)
        #expect(TextTranslation.detect("カタカナ", among: all)?.languageCode == .japanese) // kana alone
        #expect(TextTranslation.detect("我们明天去北京开会，请准备好材料。", among: all)?.languageCode == .chinese)
        #expect(TextTranslation.detect("The meeting starts at two o'clock tomorrow afternoon.", among: all)?.languageCode == .english)
        #expect(TextTranslation.detect("Cuộc họp bắt đầu lúc hai giờ chiều mai.", among: all)?.languageCode == .vietnamese)
        #expect(TextTranslation.detect("今日は会議があります", among: ["en", "vi"]) == nil) // not translatable here
        #expect(TextTranslation.detect("", among: all) == nil)
        #expect(!TextTranslation.isKana("・".unicodeScalars.first!))
    }

    @Test func joinsRecognisedLines() {
        #expect(OCR.paragraphs(from: ["来週の会議は火曜", "日の午後です。", "資料を共有して", "ください。"]) == "来週の会議は火曜日の午後です。\n資料を共有してください。")
        #expect(OCR.paragraphs(from: ["The meeting is on", "Tuesday afternoon.", "", "Thanks"]) == "The meeting is on Tuesday afternoon.\nThanks")
        #expect(OCR.paragraphs(from: ["「こんにちは」", "Tokyo 2026"]) == "「こんにちは」\nTokyo 2026")
        #expect(OCR.paragraphs(from: []) == "")
    }

    /// Real on-device Vision on a rendered picture (no network).
    @Test func recognisesJapaneseInAnImage() async throws {
        let image = Self.render("今日は会議があります。")
        let lines = try await OCR.recognize(image, language: nil)
        #expect(OCR.paragraphs(from: lines) == "今日は会議があります。")
        #expect(try await OCR.recognize(Self.render(""), language: nil).isEmpty)
    }

    @Test func refusesFilesThatAreNotImages() throws {
        let file = TestData.file("not-an-image.txt")
        try Data("hello".utf8).write(to: file)
        #expect(OCR.image(at: file) == nil)
    }

    static func render(_ text: String) -> CGImage {
        let image = NSImage(size: NSSize(width: 640, height: 120))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 640, height: 120).fill()
        (text as NSString).draw(at: NSPoint(x: 12, y: 40), withAttributes: [.font: NSFont.systemFont(ofSize: 28), .foregroundColor: NSColor.black])
        image.unlockFocus()
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    }
}

@MainActor @Suite struct TranslatePadTests {
    let vi = Locale.Language(identifier: "vi")
    let all: Set<String> = ["ja", "en", "vi"]

    @Test func emptyInputDoesNothing() {
        let pad = TranslatePad()
        pad.input = "  \n"
        #expect(!pad.canTranslate)
        pad.translate(source: nil, target: vi, supported: all)
        #expect(pad.phase == .idle && pad.config == nil)
    }

    @Test func startsATranslationPerParagraph() {
        let pad = TranslatePad()
        pad.input = "一行目です。\n二行目です。"
        pad.translate(source: nil, target: vi, supported: all)
        #expect(pad.phase == .translating && pad.busy && !pad.canTranslate)
        #expect(pad.pairs.map(\.source) == ["一行目です。", "二行目です。"])
        #expect(pad.detected?.languageCode == .japanese)
        #expect(pad.config?.source?.languageCode == .japanese && pad.config?.target?.languageCode == .vietnamese)
    }

    @Test func explainsWhatItCannotDo() {
        let pad = TranslatePad()
        pad.input = "今日は会議があります"
        pad.translate(source: nil, target: vi, supported: ["en", "vi"])
        #expect(pad.phase == .failed(TranslatePad.unknownLanguage) && pad.config == nil)
        pad.translate(source: Locale.Language(identifier: "vi"), target: vi, supported: all)
        #expect(pad.phase == .failed(TranslatePad.sameLanguage))
    }

    @Test func imageWithoutTextOrNotAnImage() async {
        let pad = TranslatePad()
        await pad.read(nil, source: nil, target: vi, supported: all)
        #expect(pad.phase == .failed(TranslatePad.notImage))
        await pad.read(TextTranslationTests.render(""), source: nil, target: vi, supported: all)
        #expect(pad.phase == .failed(TranslatePad.noText))
    }

    @Test func imageTextGoesToTheEditorAndIsTranslated() async {
        let pad = TranslatePad()
        await pad.read(TextTranslationTests.render("明日東京へ行きます。"), source: nil, target: vi, supported: all)
        #expect(pad.input == "明日東京へ行きます。")
        #expect(pad.phase == .translating && pad.pairs.count == 1)
    }

    @Test func clearResets() {
        let pad = TranslatePad()
        pad.input = "今日は"
        pad.translate(source: nil, target: vi, supported: all)
        pad.clear()
        #expect(pad.input.isEmpty && pad.pairs.isEmpty && pad.phase == .idle && pad.detected == nil)
    }
}
