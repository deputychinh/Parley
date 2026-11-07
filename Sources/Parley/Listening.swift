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
    nonisolated static func curated() -> [Clip] {
        Library.topics.flatMap { t in
            t.words.map { w in
                Clip(id: "topic:\(t.id):\(w.term)", text: w.example, translation: w.exampleTranslation, audio: nil,
                     start: 0, end: 0, origin: t.title)
            }
        }
    }
}

// MARK: - Word diff (dictation and shadowing feedback)

enum WordDiff {
    enum Kind: Hashable { case correct, wrong(String), missing, extra }
    struct Token: Hashable { let word: String; let kind: Kind }

    /// Expected words in order, each marked correct / wrong (with what was typed) / missing; typed words that match
    /// nothing are inserted as `extra`. Comparison ignores case and punctuation (`Answer.normalize`).
    static func diff(expected: String, typed: String) -> [Token] {
        let exp = words(expected), got = words(typed)
        let a = exp.map { Answer.normalize($0) }, b = got.map { Answer.normalize($0) }
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

    private static func words(_ s: String) -> [String] {
        s.split(whereSeparator: \.isWhitespace).map(String.init).filter { !Answer.normalize($0).isEmpty }
    }
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
            p.enableRate = true
            p.prepareToPlay()
            p.rate = Float(speed)
            p.currentTime = clip.start
            p.play()
            player = p
            playing = true
            let wait = clip.duration / speed
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
    var skill: Skill { self == .dictation ? .listening : .speaking }
}

struct ListeningView: View {
    @State private var meeting: [Clip] = []
    @State private var useMeeting = true
    @State private var session: ListeningPlan?
    @AppStorage("listeningSpeed") private var speed = 1.0

    private var pool: [Clip] { useMeeting && !meeting.isEmpty ? meeting : Clips.curated() }

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
            meeting = Clips.fromHistory()
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
                Label("Mỗi lượt 10 câu; đúng từ 80% số từ trở lên là đạt. Phím tắt: Space nghe lại, ↩ kiểm tra / câu tiếp, Esc kết thúc.",
                      systemImage: "keyboard")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func start(_ mode: ListeningMode) {
        let clips = Array(pool.shuffled().prefix(10))
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
    @State private var typed = ""
    @State private var result: [WordDiff.Token]?
    @State private var scores: [Double] = []
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
        .onAppear { if let c = clips.first { player.play(c, speed: speed) } }
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
                    .keyboardShortcut(.space, modifiers: [])
                    .help("Nghe lại (Space)")
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
                if mic.listening { Text("Đang nghe…").foregroundStyle(.secondary) }
            } else {
                Button("Nói lại") { result = nil; mic.heard = nil }
                    .buttonStyle(.glass)
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
        let passed = scores.count { $0 >= WordDiff.pass }
        let avg = scores.isEmpty ? 0 : scores.reduce(0, +) / Double(scores.count)
        return VStack(spacing: 16) {
            Image(systemName: !scores.isEmpty && passed == scores.count ? "trophy.fill" : "checkmark.seal.fill")
                .font(.system(size: 64)).foregroundStyle(Color.parley.gradient).symbolEffect(.bounce, options: .repeat(2))
            Text("Hoàn thành!").font(.largeTitle.weight(.bold))
            Text("Đạt \(passed)/\(scores.count) câu · trung bình \(Int((avg * 100).rounded()))% từ đúng").foregroundStyle(.secondary)
            Button { onExit() } label: { Label("Xong", systemImage: "checkmark") }
                .buttonStyle(.glassProminent).controlSize(.large).keyboardShortcut(.defaultAction)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
    }

    private func check(_ clip: Clip, _ answer: String) {
        guard result == nil, !answer.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let tokens = WordDiff.diff(expected: clip.text, typed: answer)
        let s = WordDiff.score(tokens)
        withAnimation(.snappy) { result = tokens }
        scores.append(s)
        activity.add(mode.skill, xp: XP.answer(s >= WordDiff.pass))
    }

    private func toggleMic(_ clip: Clip) async {
        if mic.listening {
            let heard = await mic.stop()
            if heard.trimmingCharacters(in: .whitespaces).isEmpty {
                mic.error = "Chưa nghe thấy gì — kiểm tra micro (System Settings → Privacy & Security → Microphone) rồi thử lại."
            } else {
                check(clip, heard)
            }
            return
        }
        player.stop()
        await mic.start(language: "en_US")
        guard mic.listening else { return }
        // Auto-stop after the sentence's length plus thinking time.
        let limit = max(clip.duration, Double(clip.text.split(separator: " ").count) * 0.45) * 1.6 + 2
        try? await Task.sleep(for: .seconds(limit))
        if mic.listening, result == nil, index < clips.count, clips[index] == clip { await toggleMic(clip) }
    }

    private func next() {
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
    var body: some View {
        tokens.reduce(Text("")) { acc, t in
            let piece: Text
            switch t.kind {
            case .correct: piece = Text(t.word).foregroundStyle(.green)
            case .wrong(let typed):
                piece = Text("\(Text(t.word).foregroundStyle(.red).underline()) \(Text("(\(typed))").foregroundStyle(.secondary).strikethrough())")
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
