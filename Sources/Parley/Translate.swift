import AppKit
import NaturalLanguage
import SwiftUI
import Translation
import UniformTypeIdentifiers
import Vision

// MARK: - Pure logic

/// Text ready to translate: paragraphs in order, and whether the input was cut at `TextTranslation.limit`.
struct PreparedText: Equatable {
    var paragraphs: [String]
    var truncated: Bool
}

enum TextTranslation {
    nonisolated static let limit = 20_000

    /// Trims, keeps the first `limit` characters and splits into non-empty lines (one paragraph per line).
    nonisolated static func prepare(_ text: String) -> PreparedText {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let truncated = trimmed.count > limit
        let kept = truncated ? String(trimmed.prefix(limit)) : trimmed
        let paragraphs = kept.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return PreparedText(paragraphs: paragraphs, truncated: truncated)
    }

    /// The language of `text` among `supported` language codes ("ja", "en", …), or nil when unsure.
    /// Any kana means Japanese: text of kanji alone is otherwise often taken for Chinese.
    nonisolated static func detect(_ text: String, among supported: Set<String>) -> Locale.Language? {
        if supported.contains("ja"), text.unicodeScalars.contains(where: isKana) { return Locale.Language(identifier: "ja") }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(String(text.prefix(2_000)))
        let hypotheses = recognizer.languageHypotheses(withMaximum: 5).sorted { $0.value > $1.value }
        for (language, probability) in hypotheses where probability >= 0.3 {
            let candidate = Locale.Language(identifier: language.rawValue)
            if let code = candidate.languageCode?.identifier, supported.contains(code) { return candidate }
        }
        return nil
    }

    /// Hiragana or katakana (U+3040–U+30FF), except the middle dot that Chinese text also uses.
    nonisolated static func isKana(_ scalar: Unicode.Scalar) -> Bool {
        (0x3040...0x30FF).contains(scalar.value) && scalar.value != 0x30FB
    }
}

enum OCR {
    /// Characters after which a recognised line ends a sentence (new paragraph).
    nonisolated static let sentenceEnds: Set<Character> = ["。", "！", "？", ".", "!", "?", "」", "』", "…"]

    /// Joins recognised lines back into sentences: lines wrap mid-sentence, Japanese and Chinese need no space
    /// between them, and a line that ends a sentence starts a new paragraph.
    nonisolated static func paragraphs(from lines: [String]) -> String {
        var out = ""
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let first = line.first else { continue }
            if let last = out.last, last != "\n", !isWide(last), !isWide(first) { out += " " }
            out += line
            if let end = line.last, sentenceEnds.contains(end) { out += "\n" }
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// CJK characters and full-width punctuation, written without spaces between words.
    nonisolated static func isWide(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value else { return false }
        return (0x3000...0x9FFF).contains(v) || (0xF900...0xFAFF).contains(v) || (0xFF00...0xFFEF).contains(v)
    }

    /// On-device text recognition. `language` nil → Japanese and English with automatic detection.
    nonisolated static func recognize(_ image: CGImage, language: Locale.Language?) async throws -> [String] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let wanted = language.map { [$0] } ?? [Locale.Language(identifier: "ja-JP"), Locale.Language(identifier: "en-US")]
        let codes = Set(wanted.compactMap { $0.languageCode })
        let usable = request.supportedRecognitionLanguages.filter { $0.languageCode.map(codes.contains) ?? false }
        if usable.isEmpty || language == nil { request.automaticallyDetectsLanguage = true }
        if !usable.isEmpty { request.recognitionLanguages = usable }
        let observations = try await request.perform(on: image)
        return observations.compactMap { $0.topCandidates(1).first?.string }
    }

    /// An image file (PNG, JPEG, HEIC, TIFF, PDF first page…) as a bitmap, or nil when it is not an image.
    nonisolated static func image(at url: URL) -> CGImage? {
        NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}

/// Interactive "drag a box" capture with the system tool; nil when the user presses Esc.
enum ScreenRegion {
    static func capture() async -> CGImage? {
        let file = FileManager.default.temporaryDirectory.appending(path: "parley-region-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: file) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", file.path] // -i: select a region, -x: no sound
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in done.resume() }
            do { try process.run() } catch { process.terminationHandler = nil; done.resume() }
        }
        return OCR.image(at: file)
    }
}

// MARK: - State

/// One "Dịch văn bản & ảnh" session: input, the request in flight and its results.
@MainActor @Observable final class TranslatePad {
    enum Phase: Equatable { case idle, reading, translating, done, failed(String) }
    struct Pair: Identifiable, Equatable {
        let id: Int
        let source: String
        var target = ""
    }

    var input = ""
    private(set) var phase: Phase = .idle
    private(set) var pairs: [Pair] = []
    private(set) var truncated = false
    private(set) var detected: Locale.Language?
    /// Set → `.translationTask` runs (and shows the system download sheet when a pack is missing).
    private(set) var config: TranslationSession.Configuration?
    /// Bumped per request, so a slower earlier request never writes into a newer one.
    private var generation = 0

    var busy: Bool { phase == .reading || phase == .translating }
    var canTranslate: Bool { !busy && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var translation: String { pairs.map(\.target).joined(separator: "\n") }

    nonisolated static let unknownLanguage = "Không nhận ra ngôn ngữ — hãy chọn ngôn ngữ nguồn"
    nonisolated static let sameLanguage = "Ngôn ngữ nguồn và ngôn ngữ đích giống nhau"
    nonisolated static let noText = "Không tìm thấy chữ trong ảnh"
    nonisolated static let notImage = "Không mở được tệp này như một ảnh"
    nonisolated static let emptyClipboard = "Bộ nhớ tạm không có chữ hay ảnh"

    /// `source` nil = detect among `supported` language codes.
    func translate(source: Locale.Language?, target: Locale.Language, supported: Set<String>) {
        let prepared = TextTranslation.prepare(input)
        guard !prepared.paragraphs.isEmpty, !busy else { return }
        generation += 1
        let from = source ?? TextTranslation.detect(prepared.paragraphs.joined(separator: "\n"), among: supported)
        detected = source == nil ? from : nil
        guard let from else { return fail(Self.unknownLanguage) }
        guard from.languageCode != target.languageCode else { return fail(Self.sameLanguage) }
        pairs = prepared.paragraphs.enumerated().map { Pair(id: $0.offset, source: $0.element) }
        truncated = prepared.truncated
        phase = .translating
        let next = TranslationSession.Configuration(source: from, target: target)
        if config?.source == next.source, config?.target == next.target { config?.invalidate() } else { config = next }
    }

    /// Called by `.translationTask` with a session for `config`.
    func run(_ session: TranslationSession) async {
        let mine = generation
        guard phase == .translating else { return }
        let requests = pairs.map { TranslationSession.Request(sourceText: $0.source, clientIdentifier: String($0.id)) }
        do {
            for try await response in session.translate(batch: requests) {
                guard mine == generation else { return }
                if let id = response.clientIdentifier.flatMap(Int.init), pairs.indices.contains(id) { pairs[id].target = response.targetText }
            }
            if mine == generation { phase = .done }
        } catch {
            guard mine == generation else { return }
            let (from, to) = (config?.source, config?.target)
            let installed = if let from, let to { await LanguageAvailability().status(from: from, to: to) == .installed } else { false }
            fail(installed ? "Không dịch được: \(error.localizedDescription)"
                           : "Chưa có gói dịch \(from.map(Model.name) ?? "") → \(to.map(Model.name) ?? ""). Tải trong Cài đặt hệ thống › Chung › Ngôn ngữ & Vùng › Ngôn ngữ dịch.")
        }
    }

    /// OCR an image into the editor, then translate it.
    func read(_ image: CGImage?, source: Locale.Language?, target: Locale.Language, supported: Set<String>) async {
        guard !busy else { return }
        guard let image else { return fail(Self.notImage) }
        generation += 1
        let mine = generation
        phase = .reading
        do {
            let text = OCR.paragraphs(from: try await OCR.recognize(image, language: source))
            guard mine == generation else { return }
            guard !text.isEmpty else { return fail(Self.noText) }
            input = text
            phase = .idle
            translate(source: source, target: target, supported: supported)
        } catch {
            if mine == generation { fail("Không đọc được ảnh: \(error.localizedDescription)") }
        }
    }

    /// "Dán": text on the clipboard is translated as is; a picture alone (screenshot, copied image) is read first.
    /// Returns false when the clipboard holds neither.
    @discardableResult
    func paste(from board: NSPasteboard, source: Locale.Language?, target: Locale.Language, supported: Set<String>) async -> Bool {
        guard !busy else { return false }
        if let text = board.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            input = text
            translate(source: source, target: target, supported: supported)
            return true
        }
        guard let image = NSImage(pasteboard: board)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            fail(Self.emptyClipboard)
            return false
        }
        await read(image, source: source, target: target, supported: supported)
        return true
    }

    func clear() {
        generation += 1
        input = ""
        pairs = []
        truncated = false
        detected = nil
        phase = .idle
    }

    private func fail(_ message: String) {
        pairs = []
        truncated = false
        phase = .failed(message)
    }
}

// MARK: - Screen

/// "Dịch văn bản & ảnh": type or paste text, open / drop / paste an image, or capture a screen region.
struct TranslateScreen: View {
    @State private var pad = TranslatePad()
    @AppStorage("translateSource", store: AppDefaults.store) private var sourceID = "auto"
    @AppStorage("translateTarget", store: AppDefaults.store) private var targetID = "vi"
    @State private var languages: [Locale.Language] = []
    @State private var importing = false

    private var source: Locale.Language? { sourceID == "auto" ? nil : Locale.Language(identifier: sourceID) }
    private var target: Locale.Language { Locale.Language(identifier: targetID) }
    private var supported: Set<String> { Set(languages.compactMap { $0.languageCode?.identifier }) }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Bilingual {
                TranscriptCard(title: sourceTitle, code: source.map(Model.code) ?? pad.detected.map(Model.code) ?? "AUTO") {
                    if !pad.input.isEmpty {
                        Button("Xoá", systemImage: "xmark.circle.fill", action: pad.clear)
                            .labelStyle(.iconOnly).buttonStyle(.borderless).foregroundStyle(.secondary).help("Xoá")
                    }
                } content: {
                    editor
                }
                TranscriptCard(title: Model.name(target), code: Model.code(target)) {
                    if pad.phase == .done, !pad.translation.isEmpty {
                        Button("Sao chép bản dịch", systemImage: "doc.on.doc") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(pad.translation, forType: .string)
                        }
                        .buttonStyle(.borderless)
                    }
                } content: {
                    result.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationTitle("Dịch văn bản & ảnh")
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            Task { await pad.read(OCR.image(at: url), source: source, target: target, supported: supported) }
            return true
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image, .pdf]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            let image = OCR.image(at: url)
            if access { url.stopAccessingSecurityScopedResource() }
            Task { await pad.read(image, source: source, target: target, supported: supported) }
        }
        .translationTask(pad.config) { session in await pad.run(session) }
        .task {
            var seen = Set<String>()
            languages = await LanguageAvailability().supportedLanguages.filter { seen.insert($0.minimalIdentifier).inserted }
                .sorted { Model.name($0).localizedCompare(Model.name($1)) == .orderedAscending }
            if DebugArgs.has("--translate-sample") { // screenshots
                pad.input = TranslateScreen.sample
                translate()
            }
        }
    }

    nonisolated static let sample = "来週の会議は火曜日の午後二時からです。\n資料は前日までに共有してください。\nよろしくお願いいたします。"

    private var sourceTitle: String {
        if let source { return Model.name(source) }
        if let detected = pad.detected { return "\(Model.name(detected)) (tự nhận diện)" }
        return "Tự nhận diện ngôn ngữ"
    }

    private func translate() { pad.translate(source: source, target: target, supported: supported) }

    private var controls: some View {
        HStack(spacing: 10) {
            Picker("Từ", selection: $sourceID) {
                Text("Tự nhận diện").tag("auto")
                Divider()
                ForEach(languages, id: \.minimalIdentifier) { Text(Model.name($0)).tag($0.minimalIdentifier) }
            }
            .frame(maxWidth: 210)
            Image(systemName: "arrow.right").foregroundStyle(.secondary).accessibilityHidden(true)
            Picker("Sang", selection: $targetID) {
                ForEach(languages, id: \.minimalIdentifier) { Text(Model.name($0)).tag($0.minimalIdentifier) }
            }
            .frame(maxWidth: 190)
            Spacer(minLength: 8)
            // Full labels when they fit, icons (with tooltips and accessibility labels) in a narrow window.
            ViewThatFits(in: .horizontal) {
                actions.labelStyle(.titleAndIcon).fixedSize()
                actions.labelStyle(.iconOnly).fixedSize()
            }
        }
        .disabled(pad.busy)
        .padding(.horizontal, 14).padding(.top, 12)
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: 8) {
            Button("Mở ảnh…", systemImage: "photo") { importing = true }
                .help("Mở ảnh hoặc PDF (hoặc kéo thả ảnh vào đây)")
            Button("Dán", systemImage: "doc.on.clipboard", action: paste)
                .help("Dán ảnh hoặc chữ từ bộ nhớ tạm")
            Button("Chụp vùng màn hình", systemImage: "viewfinder") {
                Task { // Esc → nil → nothing happens
                    guard let image = await ScreenRegion.capture() else { return }
                    await pad.read(image, source: source, target: target, supported: supported)
                }
            }
            .help("Kéo chọn một vùng bất kỳ trên màn hình (Esc để huỷ)")
            Button("Dịch", systemImage: "character.bubble", action: translate)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!pad.canTranslate)
                .help("Dịch (⌘↩)")
        }
    }

    private var editor: some View {
        TextEditor(text: $pad.input)
            .font(.title3)
            .scrollContentBackground(.hidden)
            .padding(12)
            .overlay(alignment: .topLeading) {
                if pad.input.isEmpty {
                    Text("Gõ hoặc dán chữ cần dịch, kéo thả ảnh vào đây…")
                        .font(.title3).foregroundStyle(.tertiary)
                        .padding(.horizontal, 17).padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel("Văn bản cần dịch")
    }

    @ViewBuilder private var result: some View {
        switch pad.phase {
        case .reading:
            ProgressView("Đang đọc chữ trong ảnh…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView(message, systemImage: "exclamationmark.triangle")
        case .idle where pad.pairs.isEmpty:
            ContentUnavailableView {
                Label("Dịch chữ và ảnh, không cần mạng", systemImage: "character.bubble")
            } description: {
                Text("Dán chữ, mở hoặc kéo thả ảnh, hay chụp một vùng màn hình (manga, game, tài liệu…). Nhấn ⌘↩ để dịch.")
            }
        default:
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if pad.truncated {
                        Label("Văn bản quá dài — chỉ dịch \(TextTranslation.limit.formatted()) ký tự đầu.", systemImage: "scissors")
                            .font(.callout).foregroundStyle(.orange)
                    }
                    ForEach(pad.pairs) { pair in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(pair.source).font(.callout).foregroundStyle(.secondary)
                            if pair.target.isEmpty {
                                ProgressView().controlSize(.small)
                            } else {
                                Text(pair.target).font(.title3)
                            }
                        }
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(18)
            }
        }
    }

    private func paste() {
        Task { await pad.paste(from: .general, source: source, target: target, supported: supported) }
    }
}

/// `Parley --translate-image <file> [--source ja] [--target vi]`: OCR + translation without the window, timed.
enum TranslateCLI {
    static func run(_ path: String) async throws {
        let started = Date()
        guard let image = OCR.image(at: URL(fileURLWithPath: path)) else { throw Err(TranslatePad.notImage) }
        let source = DebugArgs.value("--source").map { Locale.Language(identifier: $0) }
        let target = Locale.Language(identifier: DebugArgs.value("--target") ?? "vi")
        let text = OCR.paragraphs(from: try await OCR.recognize(image, language: source))
        print("ocr:", text)
        guard !text.isEmpty else { throw Err(TranslatePad.noText) }
        let supported = Set(await LanguageAvailability().supportedLanguages.compactMap { $0.languageCode?.identifier })
        let prepared = TextTranslation.prepare(text)
        guard let from = source ?? TextTranslation.detect(text, among: supported) else { throw Err(TranslatePad.unknownLanguage) }
        let session = TranslationSession(installedSource: from, target: target)
        for paragraph in prepared.paragraphs { print("\(target.minimalIdentifier):", try await session.translate(paragraph).targetText) }
        print(String(format: "source: %@, %d paragraphs, %.2fs", from.minimalIdentifier, prepared.paragraphs.count, Date().timeIntervalSince(started)))
    }
}
