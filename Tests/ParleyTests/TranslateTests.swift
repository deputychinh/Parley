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
        #expect(TextTranslation.detect("ｶﾀｶﾅ", among: all)?.languageCode == .japanese) // half-width katakana
        #expect(TextTranslation.detect("社長の指示", among: all)?.languageCode == .japanese) // kanji + の
        #expect(TextTranslation.detect("I love ラーメン so much", among: all)?.languageCode == .english) // loanword, not Japanese
        #expect(TextTranslation.detect("我们明天去北京开会，请准备好材料。", among: all)?.languageCode == .chinese)
        #expect(TextTranslation.detect("The meeting starts at two o'clock tomorrow afternoon.", among: all)?.languageCode == .english)
        #expect(TextTranslation.detect("Cuộc họp bắt đầu lúc hai giờ chiều mai.", among: all)?.languageCode == .vietnamese)
        #expect(TextTranslation.detect("今日は会議があります", among: ["en", "vi"]) == nil) // not translatable here
        #expect(TextTranslation.detect("", among: all) == nil)
    }

    @Test func joinsRecognisedLines() {
        #expect(OCR.paragraphs(from: ["来週の会議は火曜", "日の午後です。", "資料を共有して", "ください。"]) == "来週の会議は火曜日の午後です。\n資料を共有してください。")
        #expect(OCR.paragraphs(from: ["The meeting is on", "Tuesday afternoon.", "", "Thanks"]) == "The meeting is on Tuesday afternoon.\nThanks")
        #expect(OCR.paragraphs(from: ["「こんにちは」", "Tokyo 2026"]) == "「こんにちは」\nTokyo 2026")
        #expect(OCR.paragraphs(from: []) == "")
        // Latin next to Japanese: no space inserted at a CJK boundary, a space between two Latin lines
        #expect(OCR.paragraphs(from: ["新しいiPhone", "を買いました。"]) == "新しいiPhoneを買いました。")
        #expect(OCR.paragraphs(from: ["Version", "2.0 です。"]) == "Version 2.0 です。")
    }

    /// Real on-device Vision on a rendered picture (no network).
    @Test func recognisesJapaneseInAnImage() async throws {
        let image = Self.render("今日は会議があります。")
        let lines = try await OCR.recognize(image, language: nil)
        #expect(OCR.paragraphs(from: lines) == "今日は会議があります。")
        #expect(try await OCR.recognize(Self.render(""), language: nil).isEmpty)
    }

    @Test func refusesFilesThatAreNotImages() async throws {
        let file = TestData.file("not-an-image.txt")
        try Data("hello".utf8).write(to: file)
        #expect(OCR.image(at: file) == nil)
        #expect(await OCR.loadImage(at: file) == nil)
    }

    /// ADR 0001: a link dragged from a browser is never loaded. A `data:` URL holding a real PNG proves it offline:
    /// NSImage would open it, so only the file-URL check keeps it out.
    @Test func neverLoadsNonFileURLs() async throws {
        let image = NSImage(cgImage: Self.render("今日"), size: .zero)
        let tiff = try #require(image.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        let url = try #require(URL(string: "data:image/png;base64," + png.base64EncodedString()))
        #expect(NSImage(contentsOf: url) != nil) // the URL itself is a loadable picture
        #expect(OCR.image(at: url) == nil)
        #expect(await OCR.loadImage(at: url) == nil)
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

    /// A private pasteboard: the owner's clipboard is never touched.
    @Test func pastesTextImagesOrNothing() async {
        let board = NSPasteboard(name: NSPasteboard.Name("parley-test-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let pad = TranslatePad()

        board.clearContents()
        #expect(!(await pad.paste(from: board, source: nil, target: vi, supported: all)))
        #expect(pad.phase == .failed(TranslatePad.emptyClipboard))

        board.clearContents()
        board.setString("今日は会議があります", forType: .string)
        #expect(await pad.paste(from: board, source: nil, target: vi, supported: all))
        #expect(pad.input == "今日は会議があります" && pad.phase == .translating)

        let imagePad = TranslatePad()
        board.clearContents()
        board.writeObjects([NSImage(cgImage: TextTranslationTests.render("明日東京へ行きます。"), size: .zero)])
        #expect(await imagePad.paste(from: board, source: nil, target: vi, supported: all))
        #expect(imagePad.input == "明日東京へ行きます。" && imagePad.phase == .translating)
    }

    @Test func notesWhenTheTextWasCut() {
        let pad = TranslatePad()
        pad.input = String(repeating: "あ", count: TextTranslation.limit + 1)
        pad.translate(source: Locale.Language(identifier: "ja"), target: vi, supported: all)
        #expect(pad.truncated && pad.pairs.first?.source.count == TextTranslation.limit)
        pad.clear()
        pad.input = "短い文です"
        pad.translate(source: Locale.Language(identifier: "ja"), target: vi, supported: all)
        #expect(!pad.truncated)
    }

    /// A slower earlier request never writes into a newer one.
    @Test func staleResponsesAreIgnored() {
        let pad = TranslatePad()
        pad.input = "一つ目です。"
        pad.translate(source: nil, target: vi, supported: all)
        let first = pad.generation
        #expect(pad.receive(0, "Cái thứ nhất.", for: first) && pad.pairs[0].target == "Cái thứ nhất.")
        pad.clear()
        pad.input = "二つ目です。"
        pad.translate(source: nil, target: vi, supported: all)
        #expect(!pad.receive(0, "Cũ", for: first))
        #expect(pad.pairs[0].target.isEmpty)
        #expect(pad.receive(0, "Cái thứ hai.", for: pad.generation) && pad.pairs[0].target == "Cái thứ hai.")
        #expect(pad.receive(7, "ngoài phạm vi", for: pad.generation)) // unknown id: ignored, no crash
    }

    /// "Xoá" while the picture is still being read: the late OCR result must not come back.
    @Test func clearWhileReadingDiscardsTheResult() async {
        let pad = TranslatePad()
        let reading = Task { await pad.read(TextTranslationTests.render("明日東京へ行きます。"), source: nil, target: vi, supported: all) }
        while pad.phase != .reading { await Task.yield() }
        pad.clear()
        await reading.value
        #expect(pad.input.isEmpty && pad.phase == .idle && pad.pairs.isEmpty)
    }

    @Test func textWinsOverImageDataButAnImageFileWinsOverItsName() async throws {
        let board = NSPasteboard(name: NSPasteboard.Name("parley-test-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let image = NSImage(cgImage: TextTranslationTests.render("明日東京へ行きます。"), size: .zero)

        board.clearContents()
        board.writeObjects([image])
        board.setString("今日は会議があります", forType: .string)
        let textPad = TranslatePad()
        #expect(await textPad.paste(from: board, source: nil, target: vi, supported: all))
        #expect(textPad.input == "今日は会議があります")

        let file = TestData.file("copied.png")
        let tiff = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: file)
        board.clearContents()
        board.writeObjects([file as NSURL]) // Finder copy: file URL + its name as text
        board.setString("copied.png", forType: .string)
        let filePad = TranslatePad()
        #expect(await filePad.paste(from: board, source: nil, target: vi, supported: all))
        #expect(filePad.input == "明日東京へ行きます。")
    }

    @Test func regionCaptureNeedsPermissionAndIgnoresEsc() async {
        let pad = TranslatePad()
        var asked = false
        await pad.captureRegion(allowed: false, capture: { asked = true; return nil }, source: nil, target: vi, supported: all)
        #expect(pad.phase == .failed(TranslatePad.needsScreenPermission) && !asked)

        let esc = TranslatePad()
        esc.input = "そのまま"
        await esc.captureRegion(allowed: true, capture: { nil }, source: nil, target: vi, supported: all)
        #expect(esc.phase == .idle && esc.input == "そのまま")

        let shot = TranslatePad()
        await shot.captureRegion(allowed: true, capture: { TextTranslationTests.render("明日東京へ行きます。") },
                                 source: nil, target: vi, supported: all)
        #expect(shot.input == "明日東京へ行きます。" && shot.phase == .translating)
    }

    /// AC5: missing pack → where to download it; cancelled → nothing shown.
    @Test func failureMessages() {
        struct Boom: LocalizedError { var errorDescription: String? { "hỏng" } }
        #expect(TranslatePad.failureMessage(CancellationError(), installed: true, from: "Japanese", to: "Vietnamese") == nil)
        #expect(TranslatePad.failureMessage(Boom(), installed: true, from: "Japanese", to: "Vietnamese") == "Không dịch được: hỏng")
        let missing = TranslatePad.failureMessage(Boom(), installed: false, from: "Japanese", to: "Vietnamese")
        #expect(missing?.hasPrefix("Chưa có gói dịch Japanese → Vietnamese.") == true)
    }

    /// AC7: the copied translation is every paragraph's translation, one per line; done only when all arrived.
    @Test func finishesAndJoinsTheTranslation() {
        let pad = TranslatePad()
        pad.input = "一つ目です。\n二つ目です。"
        pad.translate(source: nil, target: vi, supported: all)
        let request = pad.generation
        pad.receive(0, "Cái thứ nhất.", for: request)
        pad.receive(1, "Cái thứ hai.", for: request)
        pad.finish(for: request - 1) // an older request finishing changes nothing
        #expect(pad.phase == .translating)
        pad.finish(for: request)
        #expect(pad.phase == .done && pad.translation == "Cái thứ nhất.\nCái thứ hai.")
    }

    /// Leaving the screen cancels the translation: the pad must not stay busy.
    @Test func cancellationNeverLeavesThePadBusy() {
        let partial = TranslatePad()
        partial.input = "一つ目です。\n二つ目です。"
        partial.translate(source: nil, target: vi, supported: all)
        partial.receive(0, "Cái thứ nhất.", for: partial.generation)
        partial.cancelled(for: partial.generation)
        #expect(partial.phase == .idle && !partial.busy && partial.canTranslate && partial.pairs[0].target == "Cái thứ nhất.")

        let complete = TranslatePad()
        complete.input = "一つ目です。"
        complete.translate(source: nil, target: vi, supported: all)
        complete.receive(0, "Cái thứ nhất.", for: complete.generation)
        complete.cancelled(for: complete.generation)
        #expect(complete.phase == .done)

        let stale = TranslatePad()
        stale.input = "一つ目です。"
        stale.translate(source: nil, target: vi, supported: all)
        stale.cancelled(for: stale.generation - 1)
        #expect(stale.phase == .translating)
    }

    @Test func announcesPhaseChanges() {
        #expect(TranslateScreen.announcement(for: .done) == "Đã dịch xong")
        #expect(TranslateScreen.announcement(for: .failed(TranslatePad.noText)) == TranslatePad.noText)
        #expect(TranslateScreen.announcement(for: .reading) != nil && TranslateScreen.announcement(for: .idle) == nil)
    }

    /// PARLEY-26: typed or ⌘V text translates on its own once; again only when the text or a language changes.
    @Test func autoTranslatesOnlyWhatChanged() {
        let ja = Locale.Language(identifier: "ja"), en = Locale.Language(identifier: "en")
        let pad = TranslatePad()
        #expect(!pad.shouldAutoTranslate(source: nil, target: vi)) // empty
        pad.input = "  \n"
        #expect(!pad.shouldAutoTranslate(source: nil, target: vi)) // blank
        pad.input = "会議です"
        #expect(pad.shouldAutoTranslate(source: nil, target: vi))
        pad.translate(source: nil, target: vi, supported: all)
        #expect(!pad.shouldAutoTranslate(source: nil, target: vi)) // busy
        pad.receive(0, "Là cuộc họp.", for: pad.generation)
        pad.finish(for: pad.generation)
        #expect(pad.phase == .done && !pad.shouldAutoTranslate(source: nil, target: vi)) // already translated
        pad.input = "会議です\n"
        #expect(!pad.shouldAutoTranslate(source: nil, target: vi)) // whitespace only
        #expect(pad.shouldAutoTranslate(source: nil, target: en)) // another target
        #expect(pad.shouldAutoTranslate(source: ja, target: vi)) // a chosen source
        pad.input = "会議です。資料も"
        #expect(pad.shouldAutoTranslate(source: nil, target: vi)) // more text
    }

    /// A failed request is not retried on its own (no error loop while nothing changes); "Xoá" forgets it.
    @Test func autoTranslateNeverRetriesAFailure() {
        let pad = TranslatePad()
        pad.input = "会議です"
        pad.translate(source: nil, target: vi, supported: ["en", "vi"]) // Japanese not translatable here
        #expect(pad.phase == .failed(TranslatePad.unknownLanguage))
        #expect(!pad.shouldAutoTranslate(source: nil, target: vi))
        pad.clear()
        pad.input = "会議です"
        #expect(pad.shouldAutoTranslate(source: nil, target: vi))
    }

    /// The debounce: a cancelled wait (a newer keystroke) translates nothing; otherwise it translates once.
    @Test func autoTranslateWaitsAndStopsWhenCancelled() async {
        #expect(TranslatePad.autoDelay == .milliseconds(600))
        let pad = TranslatePad()
        pad.input = "会議です"
        let waiting = Task { await pad.autoTranslate(after: .seconds(5), source: nil, target: vi, supported: all) }
        waiting.cancel()
        await waiting.value
        #expect(pad.phase == .idle && pad.lastRequest == nil)
        await pad.autoTranslate(after: .zero, source: nil, target: vi, supported: all, ready: { false }) // composing
        #expect(pad.phase == .idle && pad.lastRequest == nil)
        await pad.autoTranslate(after: .zero, source: nil, target: vi, supported: all)
        #expect(pad.phase == .translating && pad.automatic && pad.pairs.map(\.source) == ["会議です"])
    }

    /// AC3: text typed while a request runs is translated once that request ends.
    @Test func textTypedDuringARequestIsTranslatedAfterIt() async {
        let pad = TranslatePad()
        pad.input = "会議です"
        pad.translate(source: nil, target: vi, supported: all)
        #expect(!pad.automatic)
        let first = pad.generation
        pad.input = "会議です。資料も"
        await pad.autoTranslate(after: .zero, source: nil, target: vi, supported: all)
        #expect(pad.generation == first) // busy: waits
        pad.receive(0, "Là cuộc họp.", for: first)
        pad.finish(for: first)
        await pad.autoTranslate(after: .zero, source: nil, target: vi, supported: all) // the task re-runs when busy ends
        #expect(pad.generation == first + 1 && pad.pairs.map(\.source) == ["会議です。資料も"] && pad.automatic)
    }

    /// While typing, an automatic request on text whose language is unknown keeps the last result and shows no error;
    /// the same text is not retried. "Dịch" still shows the error.
    @Test func automaticRequestsStayQuietOnUnknownLanguage() async {
        let pad = TranslatePad()
        pad.input = "会議です"
        pad.translate(source: nil, target: vi, supported: all)
        pad.receive(0, "Là cuộc họp.", for: pad.generation)
        pad.finish(for: pad.generation)
        pad.input = "会議ですか"
        await pad.autoTranslate(after: .zero, source: nil, target: vi, supported: ["en", "vi"]) // Japanese unavailable
        #expect(pad.phase == .done && pad.pairs.first?.target == "Là cuộc họp.")
        #expect(!pad.shouldAutoTranslate(source: nil, target: vi)) // not retried
        await pad.autoTranslate(after: .zero, source: Locale.Language(identifier: "vi"), target: vi, supported: all) // same language
        #expect(pad.phase == .done)
        pad.translate(source: nil, target: vi, supported: ["en", "vi"])
        #expect(pad.phase == .failed(TranslatePad.unknownLanguage))
    }

    @Test func automaticRequestsAnnounceOnlyTheirEnd() {
        #expect(TranslateScreen.announcement(for: .translating, automatic: true) == nil)
        #expect(TranslateScreen.announcement(for: .reading, automatic: true) == nil)
        #expect(TranslateScreen.announcement(for: .done, automatic: true) == "Đã dịch xong")
        #expect(TranslateScreen.announcement(for: .translating) == "Đang dịch")
    }

    @Test func clearResets() {
        let pad = TranslatePad()
        pad.input = "今日は"
        pad.translate(source: nil, target: vi, supported: all)
        pad.clear()
        #expect(pad.input.isEmpty && pad.pairs.isEmpty && pad.phase == .idle && pad.detected == nil)
    }
}
