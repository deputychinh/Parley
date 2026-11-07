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
        ParleyApp.main()
    }
}

/// `Parley --file x.aiff` (run from the project folder): unit checks, then the real STT + translation pipeline on a file.
func selfTest(_ path: String) async throws {
    let notes = "# x\n<!-- parley: en_GB > ja -->\n\nGhi âm: a\n\n**10:00:00 AM** 🔊 Hello\n> Xin chào\n\n**10:00:05 AM** 🎤 Bye <!-- t=12.5 -->\n> Tạm biệt\n"
    let entries = Model.parse(notes)
    precondition(entries == [.init(time: "10:00:00 AM", source: .system, en: "Hello", vi: "Xin chào"),
                             .init(time: "10:00:05 AM", source: .mic, en: "Bye", vi: "Tạm biệt", offset: 12.5)], "parse broken: \(entries)")
    let langs = Model.languages(in: notes)
    precondition(langs.0.region?.identifier == "GB" && langs.1.languageCode == .japanese, "languages broken: \(langs)")
    precondition(Model.languages(in: "old file").1.languageCode == .vietnamese, "legacy languages broken")
    precondition(Model.isEcho("We need to tell them now.", of: "we need to tell them now")
                 && Model.isEcho("Emma, the system says there's a leak", of: "Emma, the system says there is a leak.")
                 && !Model.isEcho("Yes, I agree.", of: "We need to tell them now.")
                 && !Model.isEcho("", of: ""), "isEcho broken")
    let ipa = (Pronunciation.ipa("hello"), Pronunciation.ipa("meeting"), Pronunciation.ipa("cat"), Pronunciation.ipa("xyzzyq"),
               Pronunciation.ipa("Hello, Xyzzyq!"))
    precondition(ipa.0 == "/həˈloʊ/" && ipa.1 == "/ˈmitɪŋ/" && ipa.2 == "/kæt/" && ipa.3 == nil && ipa.4 == "/həˈloʊ xyzzyq/",
                 "ipa broken: \(ipa)")
    // Practice tab: answer checking, spaced repetition, part of speech
    precondition(Answer.matches("  Heritage. ", "heritage") && !Answer.matches("heritag", "heritage") && !Answer.matches("", ""),
                 "Answer.matches broken")
    precondition(Answer.score(heard: "um we need to tell them now", expected: "tell them") == 1
                 && Answer.score(heard: "sell them", expected: "tell them") == 0.5, "Answer.score broken")
    precondition(Answer.cloze("So we'll defend our heritage.", "Heritage") == "So we'll defend our ＿＿＿＿." && Answer.cloze("abc", "x") == nil,
                 "Answer.cloze broken")
    precondition(Answer.hint("leak", shown: 2) == "le__", "Answer.hint broken")
    var v = VocabItem(term: "leak", meaning: "rò rỉ", termLanguage: "en-US", meaningLanguage: "vi", example: "", exampleTranslation: "")
    precondition(v.isDue, "new word should be due")
    let t0 = Date()
    v.review(correct: true, now: t0)
    precondition(v.box == 1 && !v.isDue && abs(v.due!.timeIntervalSince(t0) - 86_400) < 1, "review(right) broken")
    v.review(correct: false, now: t0)
    precondition(v.box == 0 && v.isDue && v.reviews == 2 && v.correctCount == 1, "review(wrong) broken")
    for _ in 0..<5 { v.review(correct: true, now: t0) }
    precondition(v.mastered && v.box == 5, "mastery after 5 right answers broken")
    precondition(!v.isDue && abs(v.due!.timeIntervalSince(t0) - 30 * 86_400) < 1, "mastered words should come back in 30 days")
    v.review(correct: true, now: t0)
    precondition(v.box == 6 && abs(v.due!.timeIntervalSince(t0) - 60 * 86_400) < 1, "mastered review interval should grow")
    v.review(correct: false, now: t0)
    precondition(!v.mastered && v.isDue, "forgetting a mastered word should bring it back to learning")
    // Pronunciation tracking from per-word recognizer confidence
    let ps = await MainActor.run { () -> PronunciationStore in
        let p = PronunciationStore(file: FileManager.default.temporaryDirectory.appending(path: "parley-pron-test-\(UUID()).json"))
        var a = AttributedString("I love the heritage")
        if let r = a.range(of: "heritage") { a[r].transcriptionConfidence = 0.3 }
        if let r = a.range(of: "love") { a[r].transcriptionConfidence = 0.95 }
        p.record(a, language: "en_US")
        p.record(a, language: "en_US")
        return p
    }
    let pron = await MainActor.run { (ps.needsWork.map(\.word), ps.words["love"]?.unclear, ps.words["heritage"]?.examples) }
    precondition(pron.0 == ["heritage"] && pron.1 == 0 && pron.2 == ["I love the heritage"], "pronunciation tracking broken: \(pron)")
    // A word leaves the list only after 3 correct reads in a row; a miss resets the count.
    let streaks = await MainActor.run { () -> [Int] in
        [ps.retry("heritage", correct: true), ps.retry("heritage", correct: true), ps.retry("heritage", correct: false),
         ps.retry("heritage", correct: true), ps.retry("heritage", correct: true)]
    }
    let stillListed = await MainActor.run { ps.needsWork.map(\.word) }
    precondition(streaks == [1, 2, 0, 1, 2] && stillListed == ["heritage"], "retry streak broken: \(streaks)")
    _ = await MainActor.run { ps.retry("heritage", correct: true) }
    let cleared = await MainActor.run { ps.needsWork.isEmpty }
    precondition(cleared, "3 correct reads in a row should clear the word")
    // Learning content & daily plan
    precondition(Library.topics.count >= 14 && Library.topics.flatMap(\.words).count >= 180, "topics missing")
    precondition(Library.topics.flatMap(\.words).allSatisfy { $0.example.range(of: $0.term, options: .caseInsensitive) != nil },
                 "every topic example must contain its term")
    precondition(Library.grammar.count >= 10 && Library.grammar.allSatisfy { l in
        l.exercises.count >= 5 && l.exercises.allSatisfy { $0.options.contains($0.answer) && $0.prompt.contains("___") } }, "grammar content broken")
    precondition(Library.grammar.count >= 45 && Library.grammar.allSatisfy { $0.level != nil }
                 && Set(Library.grammar.map(\.id)).count == Library.grammar.count, "grammar curriculum incomplete")
    precondition(Library.categories.count >= 10 && Library.categories.allSatisfy { c in
        c.subtopics.allSatisfy { s in s.topic.map { id in Library.topics.contains { $0.id == id } } ?? (s.prompt != nil) } },
                 "category tree broken")
    precondition(Library.wordlist.count > 8_000 && !Library.wordlist.contains("john"), "wordlist missing or dirty")
    let picked = StudyStore.pick(count: 4, curated: ["agenda", "Sprint", "agenda"], wordlist: ["the", "sprint", "of", "and"],
                                 cursor: 0, have: ["the"])
    precondition(picked.0 == ["agenda", "Sprint", "of", "and"] && picked.1 == 4, "daily pick broken: \(picked)")
    let pos = (WordInfo.partOfSpeech("defend", in: "So we'll defend our country and our heritage."),
               WordInfo.partOfSpeech("heritage", in: "So we'll defend our country and our heritage."),
               WordInfo.partOfSpeech("Democrat nominee", in: "x"))
    precondition(pos.0 == "động từ" && pos.1 == "danh từ" && pos.2 == "cụm từ", "partOfSpeech broken: \(pos)")
    print("unit checks: ok")
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
    let model = Model()
    let vocab = VocabStore()
    let study = StudyStore()

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
