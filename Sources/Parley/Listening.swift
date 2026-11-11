import AVFoundation
import SwiftUI

// MARK: - Clips (sentences you can listen to)

/// One sentence to practise. `audio == nil` → read by the system voice (curated examples).
struct Clip: Hashable, Identifiable {
    let id: String
    let text: String
    let translation: String
    let audio: URL?
    let start: Double
    let end: Double
    let origin: String // session title or topic name

    var duration: Double { end - start }

    /// Where playback should stop in a file of `fileDuration` seconds; nil when the clip starts past the end.
    static func playEnd(start: Double, end: Double, fileDuration: Double) -> Double? {
        guard start < fileDuration else { return nil }
        return min(end, fileDuration)
    }
}

enum Clips {
    static let maxLength = 15.0
    static let minWords = 3

    /// Sentences of one saved session that have a time offset and a recording of their source.
    /// A clip runs to the next sentence of the same recording (capped at 15 s).
    nonisolated static func from(notes url: URL, text: String,
                                 exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> [Clip] {
        let entries = Model.parse(text)
        let title = SessionRow.title(url)
        var out: [Clip] = []
        for (i, e) in entries.enumerated() {
            guard let start = e.offset, e.en.split(separator: " ").count >= minWords else { continue }
            let audio = Model.media(url, "\(e.source.fileSuffix).m4a")
            guard exists(audio) else { continue }
            let next = entries[(i + 1)...].first { $0.source == e.source && ($0.offset ?? 0) > start }?.offset
            let end = min(next ?? start + maxLength, start + maxLength)
            out.append(Clip(id: "\(url.lastPathComponent)#\(i)", text: e.en, translation: e.vi, audio: audio,
                            start: max(0, start - 0.15), end: end, origin: title))
        }
        return out
    }

    /// Every usable sentence from the history folder, newest session first.
    nonisolated static func fromHistory(_ sessions: [URL] = Model.history()) -> [Clip] {
        sessions.flatMap { url in from(notes: url, text: (try? String(contentsOf: url, encoding: .utf8)) ?? "") }
    }

    /// Curated example sentences (read by the system voice) — always available.
    nonisolated static func curated() -> [Clip] { curatedClips }
    private nonisolated static let curatedClips: [Clip] = {
        Library.topics.flatMap { t in
            t.words.map { w in
                Clip(id: "topic:\(t.id):\(w.term)", text: w.example, translation: w.exampleTranslation, audio: nil,
                     start: 0, end: 0, origin: t.title)
            }
        }
    }()
}

// MARK: - Word diff (dictation and shadowing feedback)

enum WordDiff {
    enum Kind: Hashable { case correct, wrong(String), missing, extra }
    struct Token: Hashable { let word: String; let kind: Kind }

    /// Expected words in order, each marked correct / wrong (with what was typed) / missing; typed words that match
    /// nothing are inserted as `extra`. Comparison ignores case and punctuation (`Answer.normalize`).
    static func diff(expected: String, typed: String) -> [Token] {
        let exp = words(expected), got = joinCompounds(words(typed), expected: Set(words(expected).map(key)))
        let a = exp.map(key), b = got.map(key)
        var t = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1) // LCS lengths of suffixes
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                t[i][j] = a[i] == b[j] ? t[i + 1][j + 1] + 1 : max(t[i + 1][j], t[i][j + 1])
            }
        }
        var out: [Token] = []
        var missing: [Int] = [], extra: [Int] = []
        func flush() { // a gap's missing and extra words pair up as substitutions (what the learner heard instead)
            let pairs = min(missing.count, extra.count)
            for k in 0..<pairs { out.append(Token(word: exp[missing[k]], kind: .wrong(got[extra[k]]))) }
            for k in missing.dropFirst(pairs) { out.append(Token(word: exp[k], kind: .missing)) }
            for k in extra.dropFirst(pairs) { out.append(Token(word: got[k], kind: .extra)) }
            missing = []; extra = []
        }
        var i = 0, j = 0
        while i < a.count || j < b.count {
            if i < a.count, j < b.count, a[i] == b[j] {
                flush()
                out.append(Token(word: exp[i], kind: .correct))
                i += 1; j += 1
            } else if j < b.count, i == a.count || t[i][j + 1] >= t[i + 1][j] {
                extra.append(j); j += 1
            } else {
                missing.append(i); i += 1
            }
        }
        flush()
        return out
    }

    /// Share of expected words reproduced exactly (0…1).
    static func score(_ tokens: [Token]) -> Double {
        let expected = tokens.count { $0.kind != .extra }
        guard expected > 0 else { return 0 }
        return Double(tokens.count { $0.kind == .correct }) / Double(expected)
    }

    static let pass = 0.8

    /// "every one" typed for "everyone": two adjacent typed words whose join is an expected word become one word.
    static func joinCompounds(_ typed: [String], expected: Set<String>) -> [String] {
        var out: [String] = []
        var i = 0
        while i < typed.count {
            if i + 1 < typed.count, !expected.contains(key(typed[i])), expected.contains(key(typed[i]) + key(typed[i + 1])) {
                out.append(typed[i] + typed[i + 1])
                i += 2
            } else {
                out.append(typed[i])
                i += 1
            }
        }
        return out
    }

    /// Case, punctuation and apostrophes don't count: "lets" for "let's" is a typing slip, not a listening error.
    static func key(_ w: String) -> String {
        Answer.normalize(w).replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "’", with: "")
    }

    private static func words(_ s: String) -> [String] {
        s.split(whereSeparator: \.isWhitespace).map(String.init).filter { !Answer.normalize($0).isEmpty }
    }
}

// MARK: - One practice run (pure, tested)

/// Scores per sentence for one run of 10 clips. A retry replaces the sentence's score and earns no extra XP.
struct ListeningRun: Equatable {
    let dictation: Bool
    private(set) var scores: [Int: Double] = [:]   // clip index → best-so-far is not kept: the latest attempt counts

    /// Grades an answer for clip `index` and logs XP the first time this sentence is answered.
    @MainActor mutating func grade(index: Int, expected: String, answer: String, activity: ActivityStore?) -> (tokens: [WordDiff.Token], event: XPEvent?) {
        let tokens = WordDiff.diff(expected: expected, typed: answer)
        let s = WordDiff.score(tokens)
        let first = scores[index] == nil
        scores[index] = s
        let event: XPEvent? = first ? .listening(dictation: dictation, pass: s >= WordDiff.pass) : nil
        if let event { activity?.log(event) }
        return (tokens, event)
    }

    /// Sentences for a run: real meeting audio when chosen and available, otherwise the curated sentences.
    static func pool(meeting: [Clip], useMeeting: Bool, curated: [Clip] = Clips.curated()) -> [Clip] {
        useMeeting && !meeting.isEmpty ? meeting : curated
    }

    var answered: Int { scores.count }
    var passed: Int { scores.values.count { $0 >= WordDiff.pass } }
    var average: Double { scores.isEmpty ? 0 : scores.values.reduce(0, +) / Double(scores.count) }

    /// How long shadowing listens before stopping by itself: the clip (or ~0.45 s a word) × 1.6 + 2 s to start.
    static func listenLimit(clipDuration: Double, words: Int) -> Double { max(clipDuration, Double(words) * 0.45) * 1.6 + 2 }
}

// MARK: - Playback

@Observable @MainActor
final class ClipPlayer {
    var playing = false
    var error: String?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var stopTask: Task<Void, Never>?

    func play(_ clip: Clip, speed: Double) {
        stop()
        error = nil
        guard let url = clip.audio else {
            Speaker.speak(clip.text, language: Locale.Language(identifier: "en-US"), speed: speed)
            return
        }
        do {
            let p = try (player?.url == url ? player : nil) ?? AVAudioPlayer(contentsOf: url)
            guard let stopAt = Clip.playEnd(start: clip.start, end: clip.end, fileDuration: p.duration) else {
                error = "Bản ghi âm ngắn hơn câu này — có thể phiên bị dừng giữa chừng."
                return
            }
            p.enableRate = true
            p.prepareToPlay()
            p.rate = Float(speed)
            p.currentTime = clip.start
            p.play()
            player = p
            playing = true
            let wait = (stopAt - clip.start) / speed // the last line may claim 15 s past the end
            stopTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(wait))
                if !Task.isCancelled { self?.stop() }
            }
        } catch {
            self.error = "Không mở được bản ghi âm: \(error.localizedDescription)"
        }
    }

    func stop() {
        stopTask?.cancel()
        stopTask = nil
        player?.pause()
        playing = false
    }
}

// MARK: - "Luyện nghe" screen

enum ListeningMode: String, CaseIterable, Identifiable {
    case dictation, shadowing
    var id: String { rawValue }
    var title: String { self == .dictation ? "Chép chính tả" : "Nói đuổi (shadowing)" }
    var subtitle: String {
        self == .dictation ? "Nghe một câu rồi gõ lại; máy so từng từ, chỉ ra từ nghe nhầm hoặc bỏ sót."
            : "Nghe một câu rồi nói lại y như vậy; máy nghe và chấm từng từ."
    }
    var symbol: String { self == .dictation ? "keyboard" : "waveform.and.mic" }
}

struct ListeningView: View {
    @State private var meeting: [Clip] = []
    @State private var useMeeting = true
    @State private var session: ListeningPlan?
    @AppStorage("listeningSpeed", store: AppDefaults.store) private var speed = 1.0

    private var pool: [Clip] { ListeningRun.pool(meeting: meeting, useMeeting: useMeeting) }

    var body: some View {
        Group {
            if let session {
                ListeningSession(mode: session.mode, clips: session.clips, speed: $speed) {
                    withAnimation(.smooth) { self.session = nil }
                }
                .id(session.started)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                home
            }
        }
        .navigationTitle("Luyện nghe")
        .task {
            meeting = await Task.detached(priority: .userInitiated) { Clips.fromHistory() }.value
            useMeeting = !meeting.isEmpty
            if let m = DebugArgs.value("--open").flatMap(ListeningMode.init(rawValue:)) { start(m) }
        }
    }

    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Nguồn câu").font(.headline)
                        Picker("Nguồn câu", selection: $useMeeting) {
                            Text("Từ cuộc họp của tôi — giọng thật (\(meeting.count) câu)").tag(true)
                            Text("Câu mẫu theo chủ đề — giọng đọc máy (\(Clips.curated().count) câu)").tag(false)
                        }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()
                        .disabled(meeting.isEmpty)
                        if meeting.isEmpty {
                            Label("Chưa có phiên nào có ghi âm. Sau khi phiên dịch một cuộc họp, các câu bạn đã nghe sẽ xuất hiện ở đây để luyện với giọng thật.",
                                  systemImage: "info.circle")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Tốc độ phát").foregroundStyle(.secondary)
                            SpeedPicker(speed: $speed)
                        }
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
                    ForEach(ListeningMode.allCases) { mode in
                        ListeningModeCard(mode: mode, count: min(pool.count, 10)) { start(mode) }
                    }
                }
                Label("Mỗi lượt 10 câu; đúng từ 80% số từ trở lên là đạt. Phím tắt: ⌥R nghe lại, ↩ kiểm tra / câu tiếp, Esc kết thúc.",
                      systemImage: "keyboard")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func start(_ mode: ListeningMode) {
        // Debug `--type` (screenshots): keep the order so the first sentence is predictable.
        let clips = Array((DebugArgs.has("--type") ? pool : pool.shuffled()).prefix(10))
        guard !clips.isEmpty else { return }
        withAnimation(.smooth) { session = ListeningPlan(mode: mode, clips: clips) }
    }
}

struct ListeningPlan {
    let mode: ListeningMode
    let clips: [Clip]
    let started = Date()
}

struct SpeedPicker: View {
    @Binding var speed: Double
    var body: some View {
        Picker("Tốc độ", selection: $speed) {
            Text("0.75×").tag(0.75)
            Text("1×").tag(1.0)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 140)
        .help("Tốc độ phát")
    }
}

struct ListeningModeCard: View {
    let mode: ListeningMode
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: mode.symbol).font(.title).foregroundStyle(Color.parley.gradient)
                    .frame(height: 32, alignment: .leading)
                Text(mode.title).font(.headline)
                Text(mode.subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(count == 0 ? "Chưa có câu phù hợp" : "\(count) câu · Bắt đầu →")
                    .font(.callout.weight(.semibold)).foregroundStyle(count == 0 ? Color.secondary : Color.parley)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
            .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
    }
}

struct ListeningSession: View {
    let mode: ListeningMode
    let clips: [Clip]
    @Binding var speed: Double
    let onExit: () -> Void
    @Environment(ActivityStore.self) private var activity
    @State private var index = 0

    init(mode: ListeningMode, clips: [Clip], speed: Binding<Double>, onExit: @escaping () -> Void) {
        self.mode = mode
        self.clips = clips
        _speed = speed
        self.onExit = onExit
        _run = State(initialValue: ListeningRun(dictation: mode == .dictation))
    }
    @State private var typed = ""
    @State private var result: [WordDiff.Token]?
    @State private var run: ListeningRun
    @State private var player = ClipPlayer()
    @State private var mic = MicCheck()
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button { player.stop(); onExit() } label: { Label("Kết thúc", systemImage: "xmark") }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)
                ProgressView(value: Double(index), total: Double(clips.count)).tint(.parley)
                Text("\(min(index + 1, clips.count))/\(clips.count)").monospacedDigit().foregroundStyle(.secondary)
            }
            .padding(20)
            ScrollView {
                Group {
                    if index < clips.count { card(clips[index]) } else { summary }
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            guard let c = clips.first else { return }
            player.play(c, speed: speed)
            if let t = DebugArgs.value("--type") { typed = t; check(c, t) } // screenshots of the feedback state
        }
        .onDisappear {
            player.stop()
            Task { _ = await mic.stop() }
        }
    }

    private func card(_ clip: Clip) -> some View {
        Card(padding: 24) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Button { player.play(clip, speed: speed) } label: {
                        Image(systemName: player.playing ? "speaker.wave.3.fill" : "play.fill")
                            .font(.title)
                            .frame(width: 44, height: 44)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .keyboardShortcut("r", modifiers: .option) // not Space: that must type into the answer field
                    .help("Nghe lại (⌥R)")
                    .accessibilityLabel("Nghe lại")
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mode == .dictation ? "Nghe rồi gõ lại câu" : "Nghe rồi nói lại câu").font(.title3.weight(.semibold))
                        Label(clip.audio == nil ? "\(clip.origin) · giọng đọc máy" : "\(clip.origin) · giọng thật",
                              systemImage: clip.audio == nil ? "speaker.wave.2" : "waveform")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    SpeedPicker(speed: $speed)
                }
                if let e = player.error ?? mic.error {
                    Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                if mode == .dictation { dictation(clip) } else { shadowing(clip) }
                if let result { feedback(clip, result) }
            }
        }
    }

    private func dictation(_ clip: Clip) -> some View {
        HStack {
            TextField("Gõ những gì bạn nghe được…", text: $typed)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .focused($focused)
                .disabled(result != nil)
                .onSubmit { result == nil ? check(clip, typed) : next() }
            Button(result == nil ? "Kiểm tra" : "Câu tiếp") { result == nil ? check(clip, typed) : next() }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(result == nil && typed.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .onAppear { focused = true }
    }

    private func shadowing(_ clip: Clip) -> some View {
        HStack(spacing: 12) {
            if result == nil {
                Button {
                    Task { await toggleMic(clip) }
                } label: {
                    Label(mic.listening ? "Dừng & chấm điểm" : "Bắt đầu nói", systemImage: mic.listening ? "stop.circle.fill" : "mic.fill")
                }
                .buttonStyle(.glassProminent)
                .tint(mic.listening ? .red : .parley)
                .keyboardShortcut(.defaultAction)
                .disabled(mic.busy)
                if mic.listening { Text("Đang nghe…").foregroundStyle(.secondary) }
                if mic.stopping { ProgressView().controlSize(.small) }
                Spacer()
                Button("Bỏ qua câu này") { next() }
                    .buttonStyle(.borderless)
                    .disabled(mic.busy)
                    .help("Chuyển sang câu tiếp mà không chấm (khi micro không dùng được)")
            } else {
                Button("Nói lại") { result = nil; mic.heard = nil }
                    .buttonStyle(.glass)
                MyVoiceButton(mic: mic)
                Button("Câu tiếp") { next() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func feedback(_ clip: Clip, _ tokens: [WordDiff.Token]) -> some View {
        let s = WordDiff.score(tokens)
        let pct = Int((s * 100).rounded())
        return VStack(alignment: .leading, spacing: 10) {
            Label(s >= WordDiff.pass ? "Đạt — \(pct)% từ đúng" : "\(pct)% từ đúng — nghe lại và chú ý các từ tô màu",
                  systemImage: s >= WordDiff.pass ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.headline).foregroundStyle(s >= WordDiff.pass ? .green : .orange)
            DiffText(tokens: tokens).font(.title3)
            Divider()
            Text(clip.text).font(.body.weight(.medium)).textSelection(.enabled)
            if !clip.translation.isEmpty { Text(clip.translation).foregroundStyle(.secondary).textSelection(.enabled) }
            HStack(spacing: 14) {
                LegendDot(color: .green, text: "đúng")
                LegendDot(color: .red, text: "nghe nhầm (bạn ghi)")
                LegendDot(color: .orange, text: "bỏ sót")
                LegendDot(color: .secondary, text: "thừa")
            }
            .font(.caption)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private var summary: some View {
        let passed = run.passed, answered = run.answered, avg = run.average
        return VStack(spacing: 16) {
            Image(systemName: answered > 0 && passed == answered ? "trophy.fill" : "checkmark.seal.fill")
                .font(.system(size: 64)).foregroundStyle(Color.parley.gradient).symbolEffect(.bounce, options: .repeat(2))
            Text("Hoàn thành!").font(.largeTitle.weight(.bold))
            Text("Đạt \(passed)/\(answered) câu · trung bình \(Int((avg * 100).rounded()))% từ đúng").foregroundStyle(.secondary)
            Button { onExit() } label: { Label("Xong", systemImage: "checkmark") }
                .buttonStyle(.glassProminent).controlSize(.large).keyboardShortcut(.defaultAction)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
    }

    private func check(_ clip: Clip, _ answer: String) {
        guard result == nil, !answer.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let graded = run.grade(index: index, expected: clip.text, answer: answer, activity: activity)
        withAnimation(.snappy) { result = graded.tokens }
    }

    private func toggleMic(_ clip: Clip) async {
        if mic.listening { return mic.finish() }
        player.stop()
        let at = index
        // Stops when the learner stops talking; the sentence's length plus thinking time is only the cap.
        let limit = ListeningRun.listenLimit(clipDuration: clip.duration, words: clip.text.split(separator: " ").count)
        let heard = await mic.listen(language: "en_US", cap: limit)
        guard at == index, clips.indices.contains(at), clips[at] == clip else { return } // moved on meanwhile
        if let message = MicCheck.emptyResultMessage(heard: heard, error: mic.error) {
            mic.error = message
        } else {
            check(clip, heard)
        }
    }

    private func next() {
        Task { _ = await mic.stop() }
        index += 1
        typed = ""
        result = nil
        mic.heard = nil
        mic.error = nil
        if index < clips.count { player.play(clips[index], speed: speed) } else { player.stop() }
        focused = true
    }
}

struct DiffText: View {
    let tokens: [WordDiff.Token]
    /// true = the expected text is a correction of the learner's (fixes in green, kept words plain).
    var correction = false
    var body: some View {
        tokens.reduce(Text("")) { acc, t in
            let piece: Text
            switch t.kind {
            case .correct: piece = correction ? Text(t.word) : Text(t.word).foregroundStyle(.green)
            case .wrong(let typed) where correction:
                piece = Text("\(Text(typed).foregroundStyle(.secondary).strikethrough()) \(Text(t.word).foregroundStyle(.green).bold())")
            case .wrong(let typed):
                piece = Text("\(Text(t.word).foregroundStyle(.red).underline()) \(Text("(\(typed))").foregroundStyle(.secondary).strikethrough())")
            case .missing where correction: piece = Text(t.word).foregroundStyle(.green).bold()
            case .missing: piece = Text("[\(t.word)]").foregroundStyle(.orange).bold()
            case .extra: piece = Text(t.word).foregroundStyle(.secondary).strikethrough()
            }
            return Text("\(acc)\(piece) ")
        }
        .accessibilityLabel(tokens.map { t in
            switch t.kind {
            case .correct: t.word
            case .wrong(let typed): "\(t.word), bạn ghi \(typed)"
            case .missing: "\(t.word), bị bỏ sót"
            case .extra: "thừa \(t.word)"
            }
        }.joined(separator: ", "))
    }
}

struct LegendDot: View {
    let color: Color
    let text: String
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).foregroundStyle(.secondary)
        }
    }
}
