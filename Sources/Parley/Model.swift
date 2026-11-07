import AppKit
import Observation
import ScreenCaptureKit
import Speech
import Translation

@Observable @MainActor
final class Model {
    /// `en` = heard text, `vi` = translation (names predate multi-language). `offset` = seconds into the recording.
    struct Line { var source: Source; var en: String; var vi = ""; let time = Date(); var offset: Double? }
    /// One sentence read back from a saved session.
    struct Entry: Equatable { let time: String; let source: Source; let en: String; var vi: String; var offset: Double? = nil }

    var lines: [Line] = []
    var liveEN: [Source: String] = [:]
    var liveVI: [Source: String] = [:]
    var levels: [Source: Float] = [:]
    var status = "Sẵn sàng"
    var running = false
    var startedAt: Date?
    var recordScreen = false
    var needsPermission = false // Screen & System Audio Recording not granted yet
    var missingPack = false     // translation pack for the chosen pair isn't installed and the download didn't happen
    var checkInDeadline: Date?  // set while the "still recording?" prompt is up; auto-stop when it passes
    var historyVersion = 0 // bumped when sessions are added/removed so the sidebar re-reads the folder
    private(set) var stamp: String? // current session id, e.g. 2026-11-05_01-15-12
    var prepareConfig: TranslationSession.Configuration? // set → SwiftUI downloads the EN→VI pack

    /// `~/Documents/Parley`; `--data-dir <path>` (or `PARLEY_DATA_DIR`) points screenshots and tests at a scratch folder instead.
    /// The owner's real data folder (the default, and what `Seed` refuses).
    nonisolated static let defaultDataDir = URL.documentsDirectory.appending(path: "Parley")
    nonisolated static let dataDir = resolveDataDir(args: CommandLine.arguments, env: ProcessInfo.processInfo.environment)

    /// The one parser for `--data-dir`: nil = flag absent, `.success(path)`, or `.failure` for a flag that would
    /// otherwise silently fall back to the owner's real data (no value, a flag as value, or the `--data-dir=x` form).
    nonisolated static func dataDirFlag(_ args: [String]) -> Result<String, Err>? {
        if args.contains(where: { $0.hasPrefix("--data-dir=") }) { return .failure(Err("use --data-dir <folder>, not --data-dir=<folder>")) }
        guard let i = args.firstIndex(of: "--data-dir") else { return nil }
        guard args.indices.contains(i + 1), !args[i + 1].isEmpty, !args[i + 1].hasPrefix("-") else {
            return .failure(Err("--data-dir needs a folder path"))
        }
        return .success(args[i + 1])
    }

    nonisolated static func dataDirArgumentError(_ args: [String]) -> String? {
        if case .failure(let e) = dataDirFlag(args) { return e.localizedDescription }
        return nil
    }

    /// `--data-dir <path>` wins over `PARLEY_DATA_DIR`, which wins over the default; empty values are ignored.
    nonisolated static func resolveDataDir(args: [String], env: [String: String],
                                           fallback: URL = defaultDataDir) -> URL {
        // A malformed flag must never land on the real folder (Main also exits 2): use a throw-away folder instead.
        if case .failure = dataDirFlag(args) { return FileManager.default.temporaryDirectory.appending(path: "parley-invalid-data-dir") }
        let arg: String? = if case .success(let path) = dataDirFlag(args) { path } else { nil }
        let chosen = [arg, env["PARLEY_DATA_DIR"]].compactMap { $0 }.first { !$0.isEmpty }
        return chosen.map { URL(fileURLWithPath: $0) } ?? fallback
    }
    /// Language being heard (speech recognition needs a region, e.g. en_US vs en_GB).
    var sourceLocale = Locale(identifier: AppDefaults.store.string(forKey: "sourceLocale") ?? "en_US") {
        didSet { AppDefaults.store.set(sourceLocale.identifier, forKey: "sourceLocale"); translator = nil; missingPack = false }
    }
    /// Language to translate into.
    var target = Locale.Language(identifier: AppDefaults.store.string(forKey: "targetLanguage") ?? "vi") {
        didSet { AppDefaults.store.set(target.minimalIdentifier, forKey: "targetLanguage"); translator = nil; missingPack = false }
    }
    var source: Locale.Language { sourceLocale.language }
    private(set) var sourceOptions: [Locale] = []
    private(set) var targetOptions: [Locale.Language] = []

    @ObservationIgnored private let audio = SystemAudio()
    @ObservationIgnored let pronunciation: PronunciationStore

    init(activity: ActivityStore? = nil) {
        pronunciation = PronunciationStore(activity: activity)
    }
    @ObservationIgnored private var transcribers: [Source: Transcriber] = [:]
    @ObservationIgnored private var translator: TranslationSession?
    @ObservationIgnored private var pending: [Int] = []
    @ObservationIgnored private var liveTranslated: [Source: String] = [:]
    @ObservationIgnored private var pumping = false
    @ObservationIgnored private var notes: (url: URL, header: String, first: Int)?
    @ObservationIgnored private var watchdog: Task<Void, Never>?

    /// Ask every 2 h whether to keep recording; stop + save if nobody answers within 5 min.
    /// Debug: `--checkin <seconds>` shortens both (grace = same number of seconds).
    nonisolated static let checkInterval: TimeInterval = debugCheckIn ?? 2 * 3600
    nonisolated static let checkGrace: TimeInterval = debugCheckIn ?? 5 * 60
    private nonisolated static var debugCheckIn: TimeInterval? {
        let a = CommandLine.arguments
        return a.firstIndex(of: "--checkin").flatMap { a.indices.contains($0 + 1) ? TimeInterval(a[$0 + 1]) : nil }
    }

    func toggle() async { running ? await stop() : await start() }

    /// Speech languages that can also be translated, and every translation language.
    func loadLanguages() async {
        let translatable = await LanguageAvailability().supportedLanguages
        let codes = Set(translatable.compactMap { $0.languageCode })
        let speech = await SpeechTranscriber.supportedLocales
        sourceOptions = speech.filter { $0.language.languageCode.map(codes.contains) ?? false }
            .sorted { Self.name($0).localizedCompare(Self.name($1)) == .orderedAscending }
        var seen = Set<String>()
        targetOptions = translatable.filter { seen.insert($0.minimalIdentifier).inserted }
            .sorted { Self.name($0).localizedCompare(Self.name($1)) == .orderedAscending }
    }

    /// Swap directions when the target language can also be listened to.
    func swapLanguages() {
        guard let heard = sourceOptions.first(where: { $0.language.languageCode == target.languageCode }) else { return }
        let newTarget = source
        sourceLocale = heard
        target = Locale.Language(identifier: newTarget.languageCode?.identifier ?? newTarget.minimalIdentifier)
    }
    var canSwap: Bool { sourceOptions.contains { $0.language.languageCode == target.languageCode } }

    nonisolated static func name(_ locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }
    /// "English (US)" instead of "English (United States)", for tight toolbar space.
    nonisolated static func shortName(_ locale: Locale) -> String {
        let lang = locale.language.languageCode.flatMap { Locale.current.localizedString(forLanguageCode: $0.identifier) } ?? locale.identifier
        return locale.region.map { "\(lang) (\($0.identifier))" } ?? lang
    }
    nonisolated static func name(_ language: Locale.Language) -> String {
        Locale.current.localizedString(forIdentifier: language.minimalIdentifier) ?? language.minimalIdentifier
    }
    nonisolated static func code(_ language: Locale.Language) -> String {
        (language.languageCode?.identifier ?? language.minimalIdentifier).uppercased()
    }

    func start() async {
        guard !running else { return }
        let (src, dst) = (source, target)
        let availability = await LanguageAvailability().status(from: src, to: dst)
        print("start: \(sourceLocale.identifier) → \(dst.minimalIdentifier), translation pack: \(availability)")
        switch availability {
        case .installed:
            translator = translator ?? TranslationSession(installedSource: src, target: dst)
        case .supported:
            status = "Đang tải gói dịch \(Self.name(src)) → \(Self.name(dst)) (chỉ lần đầu)…"
            missingPack = false
            // invalidate() re-runs .translationTask even when the pair hasn't changed (a plain re-assign would not).
            if prepareConfig == nil { prepareConfig = .init(source: src, target: dst) } else { prepareConfig?.invalidate() }
            return
        default:
            status = "Chưa hỗ trợ dịch offline \(Self.name(src)) → \(Self.name(dst))"
            return
        }
        do {
            status = "Đang chuẩn bị…"
            try? FileManager.default.createDirectory(at: Self.dataDir, withIntermediateDirectories: true) // recorder writes here
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let stamp = f.string(from: .now)
            let includeMic = AppDefaults.store.object(forKey: "includeMic") as? Bool ?? true
            var ts: [Source: Transcriber] = [:]
            print("start: preparing speech recognizer…")
            for s in includeMic ? Source.allCases : [.system] {
                ts[s] = try await Transcriber.start(locale: sourceLocale, recordTo: Self.dataDir.appending(path: "\(stamp)-\(s.fileSuffix).m4a"),
                                                    confidence: s == .mic) // per-word confidence → "Phát âm của tôi"
            }
            transcribers = ts
            print("start: speech recognizer ready, starting capture…")
            audio.onBuffer = { [ts] buf, s in ts[s]?.feed(buf) }
            audio.onLevel = { [weak self] s, v in Task { @MainActor in if self?.running == true { self?.levels[s] = v } } }
            try await audio.start(includeMic: includeMic,
                                  recordScreenTo: recordScreen ? Self.dataDir.appending(path: "\(stamp)-screen.mov") : nil)
            self.stamp = stamp
            openNotes(stamp) // only after capture works, so failed starts leave no empty history entries
            for (s, t) in ts {
                Task {
                    do {
                        for try await r in t.module.results {
                            let kept = handle(String(r.text.characters), final: r.isFinal, from: s, offset: r.range.start.seconds)
                            if s == .mic, kept { pronunciation.record(r.text, language: sourceLocale.identifier) }
                        }
                    } catch { status = "Lỗi nhận giọng nói: \(error.localizedDescription)"; print("ERROR results \(s):", error) }
                }
            }
            running = true
            missingPack = false
            scheduleCheckIn()
            needsPermission = false
            startedAt = .now
            historyVersion += 1
            status = recordScreen ? "Đang nghe và quay màn hình" : "Đang nghe"
        } catch {
            print("ERROR start:", error)
            if (error as NSError).domain == SCStreamErrorDomain, (error as NSError).code == SCStreamError.userDeclined.rawValue {
                needsPermission = true
                status = "Cần cấp quyền ghi âm hệ thống"
            } else {
                status = "Không bắt đầu được: \(error.localizedDescription)"
            }
            await audio.stop()
            transcribers = [:]
        }
    }

    func stop() async {
        watchdog?.cancel()
        checkInDeadline = nil
        await audio.stop()
        for t in transcribers.values { try? await t.finish() }
        transcribers = [:]
        running = false
        startedAt = nil
        levels = [:]
        historyVersion += 1
        status = "Đã lưu phiên vào Lịch sử"
    }

    /// Opens the exact System Settings pane; the app is already listed there after its first capture attempt.
    func openPermissionSettings() {
        CGRequestScreenCaptureAccess()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    /// macOS only applies a newly granted screen/audio capture permission after the app restarts.
    func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }

    /// "Keep recording" answer: hide the prompt and ask again a full interval from now.
    func keepRunning() {
        checkInDeadline = nil
        scheduleCheckIn()
    }

    func scheduleCheckIn() {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.checkInterval))
            guard let self, self.running, !Task.isCancelled else { return }
            self.checkInDeadline = .now + Self.checkGrace
            NSApp?.requestUserAttention(.criticalRequest) // bounce the Dock icon (no NSApp in the CLI self-test)
            try? await Task.sleep(for: .seconds(Self.checkGrace))
            guard !Task.isCancelled, self.checkInDeadline != nil else { return }
            print("auto-stop: no answer to check-in")
            await self.stop()
            self.status = "Đã tự dừng vì không có phản hồi — phiên đã được lưu"
        }
    }

    /// Called after the system download sheet closes; only continue if the pack really is there now.
    func translationPrepared() async {
        let ok = await LanguageAvailability().status(from: source, to: target) == .installed
        print("start: download sheet closed, pack installed: \(ok)")
        guard ok else { return packStillMissing() }
        prepareConfig = nil
        await start()
    }

    func packStillMissing() {
        missingPack = true
        status = "Chưa có gói dịch \(Self.name(source)) → \(Self.name(target))"
    }

    func openLanguageSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension")!)
    }

    /// Moves a session's notes and recordings to the Trash (recoverable).
    func trash(_ notesURL: URL) {
        let stamp = notesURL.deletingPathExtension().lastPathComponent
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.dataDir, includingPropertiesForKeys: nil)) ?? []
        for f in files where f.lastPathComponent.hasPrefix(stamp) { try? FileManager.default.trashItem(at: f, resultingItemURL: nil) }
        historyVersion += 1
    }

    /// Returns true when a final sentence became a transcript line of its own (not dropped as speaker echo).
    @discardableResult
    private func handle(_ text: String, final: Bool, from s: Source, offset: Double? = nil) -> Bool {
        var kept = false
        if final {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { kept = commit(t, vi: liveVI[s] ?? "", from: s, offset: offset?.isFinite == true ? offset : nil) } // commit before clearing live → no blank gap
            liveEN[s] = nil; liveVI[s] = nil; liveTranslated[s] = nil
        } else {
            if s == .mic, Self.isEcho(text, of: liveEN[.system] ?? "") { return false }
            liveEN[s] = text
        }
        Task { await pump() }
        return kept
    }

    /// `vi` = latest live translation, shown until the proper one replaces it.
    private func commit(_ t: String, vi: String, from s: Source, offset: Double?) -> Bool {
        // Mic picking up the speakers produces the same sentence on both sources; keep a single 🔊 line.
        let recent = lines.indices.suffix(8).filter { Date.now.timeIntervalSince(lines[$0].time) < 10 }
        if s == .mic, recent.contains(where: { lines[$0].source == .system && Self.isEcho(t, of: lines[$0].en) }) { return false }
        if s == .system, let i = recent.last(where: { lines[$0].source == .mic && Self.isEcho(t, of: lines[$0].en) }) {
            lines[i].source = .system
            lines[i].en = t
            pending.append(i)
            return false
        }
        lines.append(Line(source: s, en: t, vi: vi, offset: offset))
        pending.append(lines.count - 1)
        return true
    }

    /// True when most words of `a` also appear in `b` (speech recognizers rarely produce identical punctuation).
    nonisolated static func isEcho(_ a: String, of b: String) -> Bool {
        func words(_ s: String) -> Set<String> {
            Set(s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
        }
        let wa = words(a), wb = words(b)
        guard !wa.isEmpty, !wb.isEmpty else { return false }
        return Double(wa.intersection(wb).count) / Double(max(wa.count, wb.count)) >= 0.6
    }

    /// One translation at a time: finalized lines first (in order), then only the newest partial per source.
    private func pump() async {
        guard !pumping, let translator else { return }
        pumping = true
        defer { pumping = false }
        while true {
            if !pending.isEmpty {
                let i = pending.removeFirst()
                let src = lines[i].en
                let vi = (try? await translator.translate(src).targetText) ?? "⚠︎ không dịch được"
                if lines[i].en == src { lines[i].vi = vi } // an echo merge may have replaced the text meanwhile
                writeNotes()
            } else if let s = Source.allCases.first(where: { liveEN[$0] != nil && liveEN[$0] != liveTranslated[$0] }),
                      let src = liveEN[s] {
                liveTranslated[s] = src
                let vi = (try? await translator.translate(src).targetText) ?? ""
                if liveTranslated[s] == src { liveVI[s] = vi } // a final may have cleared it meanwhile
            } else {
                return
            }
        }
    }

    // MARK: - Sessions on disk

    /// Notes file `<stamp>.md` for lines from here on; recordings share the same stamp.
    private func openNotes(_ stamp: String) {
        let video = recordScreen ? ", video `\(stamp)-screen.mov`" : ""
        let langs = "<!-- parley: \(sourceLocale.identifier) > \(target.minimalIdentifier) -->\n"
        let header = "# Parley — \(stamp)\n\(langs)\nGhi âm: `\(stamp)-may.m4a` (âm thanh máy), `\(stamp)-mic.m4a` (micro)\(video)\n\n"
        notes = (Self.dataDir.appending(path: "\(stamp).md"), header, lines.count)
        writeNotes()
    }

    /// Rewrites the whole session file so merged/relabelled lines stay correct (a few KB, cheap).
    private func writeNotes() {
        guard let notes else { return }
        let body = lines[notes.first...].map { l -> String in
            let t = l.offset.map { String(format: " <!-- t=%.1f -->", $0) } ?? "" // invisible when the .md is rendered
            return "**\(l.time.formatted(date: .omitted, time: .standard))** \(l.source.tag)\(l.en)\(t)\n> \(l.vi)\n\n"
        }.joined()
        try? Data((notes.header + body).utf8).write(to: notes.url, options: .atomic)
    }

    /// Past sessions, newest first.
    nonisolated static func history() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dataDir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "md" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    nonisolated static func date(of notesURL: URL) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f.date(from: notesURL.deletingPathExtension().lastPathComponent)
    }

    /// Sibling media file of a session, e.g. media(url, "screen.mov").
    nonisolated static func media(_ notesURL: URL, _ suffix: String) -> URL {
        URL(fileURLWithPath: notesURL.deletingPathExtension().path + "-" + suffix)
    }

    /// Languages recorded in a notes header; sessions from before multi-language support were English → Vietnamese.
    nonisolated static func languages(in text: String) -> (Locale.Language, Locale.Language) {
        guard let r = text.range(of: "<!-- parley: "), let end = text[r.upperBound...].range(of: " -->") else {
            return (Locale.Language(identifier: "en-US"), Locale.Language(identifier: "vi"))
        }
        let parts = text[r.upperBound..<end.lowerBound].components(separatedBy: " > ")
        guard parts.count == 2 else { return (Locale.Language(identifier: "en-US"), Locale.Language(identifier: "vi")) }
        return (Locale(identifier: parts[0]).language, Locale.Language(identifier: parts[1]))
    }

    /// Reads a notes file back: "**time** 🔊 heard sentence" followed by "> translation".
    nonisolated static func parse(_ text: String) -> [Entry] {
        var out: [Entry] = []
        for line in text.split(separator: "\n") {
            if line.hasPrefix("**"), let close = line.range(of: "** ", range: line.index(line.startIndex, offsetBy: 2)..<line.endIndex) {
                let time = String(line[line.index(line.startIndex, offsetBy: 2)..<close.lowerBound])
                var rest = String(line[close.upperBound...])
                var offset: Double?
                if let c = rest.range(of: " <!-- t=") {
                    offset = Double(rest[c.upperBound...].prefix { $0 != " " })
                    rest = String(rest[..<c.lowerBound])
                }
                var source = Source.system
                for s in Source.allCases where rest.hasPrefix(s.tag) { source = s; rest.removeFirst(s.tag.count) }
                out.append(Entry(time: time, source: source, en: rest, vi: "", offset: offset))
            } else if line.hasPrefix("> "), !out.isEmpty {
                out[out.count - 1].vi = String(line.dropFirst(2))
            }
        }
        return out
    }
}
