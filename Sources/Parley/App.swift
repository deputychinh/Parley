import AVFoundation
import SwiftUI
import Translation

@main
enum Main {
    static func main() {
        setvbuf(stdout, nil, _IOLBF, 0) // line-buffer so `open --stdout` logs appear live
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--file"), i + 1 < args.count {
            Task {
                do { try await selfTest(args[i + 1]); exit(0) } catch { print("FAIL:", error.localizedDescription); exit(1) }
            }
            dispatchMain()
        }
        if args.contains("--print-data-dir") { // tests: proves `--data-dir` / PARLEY_DATA_DIR reach the app
            print(Model.dataDir.path)
            exit(0)
        }
        if args.contains("--ai-eval") { // `make ai-eval`: on-device model quality + latency (needs Apple Intelligence)
            Task { @MainActor in exit(await AIEval.run() ? 0 : 1) }
            dispatchMain()
        }
        if args.contains("--seed") { // sample data for screenshots (scripts/shot.sh)
            guard let dir = Seed.folder(in: args) else { print("FAIL: --seed needs a folder"); exit(1) }
            do { try Seed.write(to: dir); exit(0) } catch { print("FAIL:", error.localizedDescription); exit(1) }
        }
        ParleyApp.main()
    }
}

/// `Parley --file x.aiff`: the real STT + translation pipeline on a file (`--ai`: on-device model, `--checkin n`: auto-stop).
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

    let en = Locale.Language(identifier: "en"), vi = Locale.Language(identifier: "vi")
    let t = try await Transcriber.start(confidence: true)
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
    print("EN:", heard)
    let translated = try await TranslationSession(installedSource: en, target: vi).translate(heard).targetText
    print("VI:", translated)
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
            ContentView(model: delegate.model, vocab: delegate.vocab, study: delegate.study)
                .environment(delegate.activity)
                .frame(minWidth: 480, minHeight: 320)
        }
        .defaultSize(width: 1200, height: 740)
        .commands { ParleyCommands(model: delegate.model) }

        // Picture-in-picture style: floats above meeting apps, starts in the bottom-right corner.
        Window("Parley Mini", id: "mini") {
            MiniView(model: delegate.model)
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

        Settings { SettingsView() }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let activity: ActivityStore
    let model: Model
    let vocab: VocabStore
    let study: StudyStore

    override init() {
        let activity = ActivityStore() // every store logs XP into it
        self.activity = activity
        model = Model(activity: activity)
        vocab = VocabStore(activity: activity)
        study = StudyStore(activity: activity)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task.detached(priority: .utility) { _ = Pronunciation.ipa("a") } // warm the 135k-word dictionary off the main thread
    }

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
