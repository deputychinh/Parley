import AVFoundation
import SwiftUI
import Translation

@main
enum Main {
    static func main() {
        setvbuf(stdout, nil, _IOLBF, 0) // line-buffer so `open --stdout` logs appear live
        let args = CommandLine.arguments
        if let problem = Model.dataDirArgumentError(args) { print("FAIL:", problem); exit(2) } // never fall back to real data
        if AppDefaults.refusesSandboxedRun(bundleID: Bundle.main.bundleIdentifier, sandboxed: AppDefaults.sandboxed), !args.contains("--seed"),
           !args.contains("--print-data-dir") {
            print("FAIL: --data-dir runs use build/Parley-sandbox.app (make sandbox-app), never the real app")
            exit(2)
        }
        if let i = args.firstIndex(of: "--file"), i + 1 < args.count {
            Task {
                do { try await selfTest(args[i + 1]); exit(0) } catch { print("FAIL:", error.localizedDescription); exit(1) }
            }
            dispatchMain()
        }
        if let path = DebugArgs.value("--translate-image") { // CLI evidence + timing for "Dịch văn bản & ảnh"
            Task {
                do { try await TranslateCLI.run(path); exit(0) } catch { print("FAIL:", error.localizedDescription); exit(1) }
            }
            dispatchMain()
        }
        if args.contains("--print-data-dir") { // tests: proves `--data-dir` / PARLEY_DATA_DIR reach the app
            print(Model.dataDir.path)
            exit(0)
        }
        if args.contains("--ai-eval") { // `make ai-eval`: on-device model quality + latency (needs Apple Intelligence)
            Task { @MainActor in
                let chat = await AIEval.run()
                let writing = await AIEval.runWriting()
                exit(chat && writing ? 0 : 1)
            }
            dispatchMain()
        }
        if args.contains("--seed") { // sample data for screenshots (scripts/shot.sh)
            guard let dir = Seed.folder(in: args) else { print("FAIL: --seed needs a folder"); exit(1) }
            do { try Seed.write(to: dir); exit(0) } catch { print("FAIL:", error.localizedDescription); exit(1) }
        }
        ParleyApp.main()
    }
}

/// `Parley --file x.aiff [--source ja_JP --target en]`: the real STT + translation pipeline on a file (`--ai`: on-device model, `--checkin n`: auto-stop).
func selfTest(_ path: String) async throws {
    // Unit checks live in Tests/ParleyTests (`make test`); this runs the real on-device pipeline.
    if CommandLine.arguments.contains("--ai") { // on-device example sentences (slow, needs Apple Intelligence)
        let t0 = Date()
        let ex = await ExampleWriter.examples(for: ["leverage", "deadline", "ambiguous", "negotiate"])
        print(String(format: "ai examples (%.1fs):", Date().timeIntervalSince(t0)), ex)
        precondition(!ex.isEmpty, "on-device example generation returned nothing")
        let t1 = Date()
        let topic = try await ExampleWriter.topic(about: "football (soccer) matches and players")
        let usable = topic.words.filter { $0.example.range(of: $0.term, options: .caseInsensitive) != nil }
        print(String(format: "ai topic (%.1fs): %@ — %d words, %d usable:", Date().timeIntervalSince(t1), topic.title, topic.words.count, usable.count),
              usable.prefix(4).map { "\($0.term): \($0.example)" })
        precondition(usable.count >= 6, "AI topic too small")
    }

    // Run with `--checkin 1`: nobody answers the prompt → the session must stop by itself.
    if Model.checkInterval < 10 {
        let m = await MainActor.run { () -> Model in
            let m = Model()
            m.running = true
            m.scheduleCheckIn()
            return m
        }
        try await Task.sleep(for: .seconds(Model.checkInterval * 0.5))
        let early = await MainActor.run { (m.running, m.checkInDeadline) }
        precondition(early.0 && early.1 == nil, "check-in fired too early")
        try await Task.sleep(for: .seconds(Model.checkInterval * 0.5 + 0.3))
        let prompted = await MainActor.run { m.checkInDeadline != nil }
        precondition(prompted, "check-in prompt never shown")
        try await Task.sleep(for: .seconds(Model.checkGrace + 0.5))
        let after = await MainActor.run { (m.running, m.checkInDeadline) }
        precondition(!after.0 && after.1 == nil, "auto-stop broken: running=\(after.0)")
        print("auto-stop: ok")
    }

    let (source, target) = Model.fileRunLanguages(CommandLine.arguments)
    let t = try await Transcriber.start(locale: source, confidence: true)
    let collector = Task {
        var out: [String] = []
        for try await r in t.module.results where r.isFinal {
            let conf = r.text.runs.compactMap { run in run.transcriptionConfidence.map { "\(String(r.text[run.range].characters).trimmingCharacters(in: .whitespaces))=\(String(format: "%.2f", $0))" } }
            print("  confidence:", conf.joined(separator: " "))
            print(String(format: "  t=%.1fs", r.range.start.seconds), String(r.text.characters)) // offsets used for click-to-seek
            out.append(String(r.text.characters))
        }
        return out.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
    let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
    while file.framePosition < file.length {
        let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096)!
        try file.read(into: buf)
        t.feed(buf)
    }
    try await t.finish()
    let heard = try await collector.value
    print("\(source.identifier):", heard)
    let translated = try await TranslationSession(installedSource: source.language, target: target).translate(heard).targetText
    print("\(target.minimalIdentifier):", translated)
    guard !heard.isEmpty, !translated.isEmpty else { throw Err("empty output") }
}

/// Debug/screenshot flags: `--open <lesson|category|topic|practice-mode id>`, `--select <word>`, `--mini`.
enum DebugArgs {
    static func value(_ flag: String) -> String? {
        let a = CommandLine.arguments
        return a.firstIndex(of: flag).flatMap { a.indices.contains($0 + 1) ? a[$0 + 1] : nil }
    }
    static func has(_ flag: String) -> Bool { CommandLine.arguments.contains(flag) }
}

struct ParleyApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        Window(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Parley", id: "main") {
            ContentView(model: delegate.model, vocab: delegate.vocab, study: delegate.study, writing: delegate.writing, reading: delegate.reading)
                .environment(delegate.activity)
                .defaultAppStorage(AppDefaults.store)
                .frame(minWidth: 480, minHeight: 320)
        }
        .defaultSize(width: 1200, height: 740)
        .commands { ParleyCommands(model: delegate.model) }

        // Picture-in-picture style: floats above meeting apps, starts in the bottom-right corner.
        Window("Parley Mini", id: "mini") {
            MiniView(model: delegate.model)
                .defaultAppStorage(AppDefaults.store)
        }
        .windowLevel(.floating)
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .windowResizability(.contentMinSize)
        .defaultWindowPlacement { _, context in
            let screen = context.defaultDisplay.visibleRect
            let size = CGSize(width: 460, height: 280)
            return WindowPlacement(CGPoint(x: screen.maxX - size.width - 20, y: screen.maxY - size.height - 20), size: size)
        }

        Settings { SettingsView().defaultAppStorage(AppDefaults.store) }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let activity: ActivityStore
    let model: Model
    let vocab: VocabStore
    let study: StudyStore
    let writing: WritingStore
    let reading: ReadingStore

    override init() {
        let activity = ActivityStore() // every store logs XP into it
        self.activity = activity
        model = Model(activity: activity)
        vocab = VocabStore(activity: activity)
        study = StudyStore(activity: activity)
        writing = WritingStore(activity: activity)
        reading = ReadingStore(activity: activity)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDefaults.removeStaleSandboxDomains()
        AppDefaults.cleanUpOnSIGTERM()
        Reminder.activity = activity
        activity.onGoalMet = { Reminder.reschedule() }
        Reminder.reschedule()
        // keep the 7-day window and today's "còn X XP" text current while the app stays open
        let nc = NotificationCenter.default
        for name in [NSApplication.didBecomeActiveNotification, .NSCalendarDayChanged] {
            nc.addObserver(forName: name, object: nil, queue: .main) { _ in MainActor.assumeIsolated { Reminder.reschedule() } }
        }
        Task.detached(priority: .utility) { _ = Pronunciation.ipa("a") } // warm the 135k-word dictionary off the main thread
    }

    func applicationWillTerminate(_ notification: Notification) { AppDefaults.removeOwnSandboxDomain() }

    // Keep running (and recording) when switching between the main and mini windows; ⌘Q quits.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// ⌘Q while running would leave the .mov/.m4a files unfinalized (unplayable): stop cleanly first.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.running else { return .terminateNow }
        Task {
            await model.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
