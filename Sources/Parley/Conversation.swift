import Foundation
import FoundationModels
import SwiftUI

// MARK: - Scenarios

/// A role-play situation. `role` and `opener` are English (what the AI says); title/goal are for the learner (Vietnamese).
struct Scenario: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    let goal: String
    let role: String
    let opener: String

    static let all: [Scenario] = [
        Scenario(id: "standup", title: "Họp daily standup", symbol: "person.3.fill",
                 goal: "Kể việc hôm qua, việc hôm nay và vướng mắc của bạn.",
                 role: "You are Alex, the friendly scrum master of a software team, running the daily standup.",
                 opener: "Morning! Let's start the standup. What did you work on yesterday?"),
        Scenario(id: "interview", title: "Phỏng vấn xin việc (IT)", symbol: "briefcase.fill",
                 goal: "Giới thiệu bản thân, kinh nghiệm và một dự án bạn tự hào.",
                 role: "You are Sarah, an engineering manager interviewing a candidate for a software developer role.",
                 opener: "Thanks for coming in today. Could you tell me a little about yourself?"),
        Scenario(id: "deadline", title: "Thương lượng dời deadline", symbol: "calendar.badge.exclamationmark",
                 goal: "Giải thích vì sao trễ và đề xuất ngày mới hợp lý.",
                 role: "You are Mark, a product manager who wants the feature shipped on Friday as planned.",
                 opener: "Hi, I heard there might be a problem with Friday's release. What's going on?"),
        Scenario(id: "codereview", title: "Trao đổi về code review", symbol: "chevron.left.forwardslash.chevron.right",
                 goal: "Giải thích lựa chọn thiết kế của bạn và phản hồi góp ý.",
                 role: "You are Priya, a senior developer reviewing the learner's pull request; you have a few questions.",
                 opener: "I looked at your pull request. Why did you decide to add a cache here?"),
        Scenario(id: "smalltalk", title: "Trò chuyện xã giao", symbol: "cup.and.saucer.fill",
                 goal: "Nói chuyện tự nhiên về cuối tuần, sở thích, công việc.",
                 role: "You are Tom, a friendly coworker chatting by the coffee machine.",
                 opener: "Hey! How was your weekend? Did you do anything fun?"),
        Scenario(id: "support", title: "Hỗ trợ khách hàng", symbol: "headset",
                 goal: "Bạn là nhân viên hỗ trợ: hỏi rõ vấn đề và hướng dẫn khách.",
                 role: "You are Linda, a slightly frustrated customer whose app login stopped working this morning.",
                 opener: "Hi, I can't log in to my account since this morning. Can you help me?"),
        Scenario(id: "restaurant", title: "Gọi món ở nhà hàng", symbol: "fork.knife",
                 goal: "Hỏi món, gọi món, hỏi về dị ứng và xin hoá đơn.",
                 role: "You are a polite waiter at a busy restaurant in London.",
                 opener: "Good evening! Are you ready to order, or would you like a few more minutes?"),
        Scenario(id: "hotel", title: "Nhận phòng khách sạn", symbol: "bed.double.fill",
                 goal: "Nhận phòng, hỏi giờ ăn sáng, Wi-Fi và trả phòng muộn.",
                 role: "You are a receptionist at a hotel front desk.",
                 opener: "Welcome! Do you have a reservation with us?"),
        Scenario(id: "airport", title: "Làm thủ tục sân bay", symbol: "airplane",
                 goal: "Làm thủ tục, gửi hành lý, chọn chỗ ngồi.",
                 role: "You are a check-in agent at an international airport.",
                 opener: "Good morning. Where are you flying to today? May I see your passport?"),
        Scenario(id: "doctor", title: "Đi khám bệnh", symbol: "stethoscope",
                 goal: "Mô tả triệu chứng, thời gian bị và hỏi cách dùng thuốc.",
                 role: "You are a calm, kind general practitioner seeing a patient.",
                 opener: "Hello, please have a seat. What brings you in today?"),
    ]
}

enum CEFR: String, CaseIterable, Identifiable {
    case a2 = "A2", b1 = "B1", b2 = "B2", c1 = "C1"
    var id: String { rawValue }
    var hint: String {
        switch self {
        case .a2: "very simple words and short sentences (A2 level)"
        case .b1: "everyday words and clear sentences (B1 level)"
        case .b2: "natural workplace English (B2 level)"
        case .c1: "rich, idiomatic English (C1 level)"
        }
    }
}

// MARK: - Model output

@Generable struct CoachTurn {
    @Guide(description: "Your next line in the role-play: 1 to 3 short sentences, stay in character, end with a question when natural")
    var reply: String
    @Guide(description: "The learner's last message rewritten with only grammar, word-choice and spelling mistakes fixed; identical if it had no mistakes")
    var corrected: String
    @Guide(description: "A more natural way a native speaker would say the learner's message")
    var natural: String
    @Guide(description: "One sentence in Vietnamese naming the grammar rule behind the most important mistake, e.g. 'Dùng quá khứ đơn (fixed, wrote) vì việc xảy ra hôm qua.' If there was no mistake, a short Vietnamese compliment")
    var tipVi: String
}

/// Pure, tested pieces of the conversation coach.
enum Coach {
    static let maxInput = 400

    static func instructions(_ s: Scenario, _ level: CEFR) -> String {
        """
        You are an English conversation partner for a Vietnamese adult learner. \(s.role) \
        Stay in this role and keep the conversation going with \(level.hint). Never switch to Vietnamese in `reply`. \
        After each learner message you also act as a careful teacher: fix real mistakes only, never change a correct \
        sentence just for style in `corrected`, and put style suggestions in `natural`.
        """
    }

    /// Trimmed, length-capped learner text; nil when there is nothing to send.
    static func clean(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        return String(t.prefix(maxInput))
    }

    /// The model's `corrected` counts as a correction only when the words really differ (not just case, punctuation
    /// or apostrophes).
    static func hasMistake(original: String, corrected: String) -> Bool {
        let c = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        return !c.isEmpty && key(original) != key(c)
    }

    /// `natural` is worth showing only when it differs from what the learner (or the correction) already said.
    static func showsNatural(original: String, corrected: String, natural: String) -> Bool {
        let n = key(natural)
        return !n.isEmpty && n != key(original) && n != key(corrected)
    }

    private static func key(_ s: String) -> String {
        s.split(whereSeparator: \.isWhitespace).map { WordDiff.key(String($0)) }.filter { !$0.isEmpty }.joined(separator: " ")
    }
}

// MARK: - Session state

struct ChatLine: Identifiable, Hashable {
    enum Who: Hashable { case ai, learner }
    let id = UUID()
    let who: Who
    let text: String
    var spoken = false
    var corrected: String?
    var natural: String?
    var tip: String?
}

@Observable @MainActor
final class ConversationModel {
    let scenario: Scenario
    let level: CEFR
    private(set) var lines: [ChatLine] = []
    var thinking = false
    var error: String?
    @ObservationIgnored private var session: LanguageModelSession
    @ObservationIgnored private let activity: ActivityStore?

    init(scenario: Scenario, level: CEFR, activity: ActivityStore? = nil) {
        self.scenario = scenario
        self.level = level
        self.activity = activity
        session = LanguageModelSession(instructions: Coach.instructions(scenario, level))
        lines = [ChatLine(who: .ai, text: scenario.opener)]
    }

    var learnerTurns: Int { lines.count { $0.who == .learner } }
    var corrections: [ChatLine] { lines.filter { $0.who == .learner && $0.corrected != nil } }

    /// Sends one learner message; returns the AI reply (nil on failure, with `error` set and the message removed).
    func send(_ raw: String, spoken: Bool) async -> String? {
        guard let text = Coach.clean(raw), !thinking else { return nil }
        error = nil
        lines.append(ChatLine(who: .learner, text: text, spoken: spoken))
        let index = lines.count - 1
        thinking = true
        defer { thinking = false }
        let last = lines.dropLast().last { $0.who == .ai }?.text ?? scenario.opener
        do {
            let turn = try await session.respond(to: "You said: \"\(last)\"\nLearner: \"\(text)\"", generating: CoachTurn.self).content
            if Coach.hasMistake(original: text, corrected: turn.corrected) { lines[index].corrected = turn.corrected }
            if Coach.showsNatural(original: text, corrected: turn.corrected, natural: turn.natural) { lines[index].natural = turn.natural }
            lines[index].tip = turn.tipVi.isEmpty ? nil : turn.tipVi
            let reply = turn.reply.trimmingCharacters(in: .whitespacesAndNewlines)
            let shown = reply.isEmpty ? "Sorry, could you say that again?" : reply
            lines.append(ChatLine(who: .ai, text: shown))
            activity?.log(.turn(spoken: spoken))
            return shown
        } catch let e as LanguageModelSession.GenerationError {
            if case .exceededContextWindowSize = e {
                error = "Cuộc hội thoại đã quá dài với AI trên máy. Hãy kết thúc và bắt đầu lượt mới."
            } else {
                error = "AI chưa trả lời được: \(e.localizedDescription)"
            }
        } catch {
            self.error = "AI chưa trả lời được: \(error.localizedDescription)"
        }
        lines.remove(at: index) // let the learner edit and resend
        return nil
    }
}

// MARK: - "Hội thoại AI" screen

struct ConversationView: View {
    let vocab: VocabStore
    @Environment(ActivityStore.self) private var activity
    @State private var level = CEFR.b1
    @State private var model: ConversationModel?

    var body: some View {
        Group {
            if !ExampleWriter.available {
                AIUnavailableView()
            } else if let model {
                ConversationSession(model: model, vocab: vocab) {
                    withAnimation(.smooth) { self.model = nil }
                }
                .id(ObjectIdentifier(model))
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                picker
            }
        }
        .navigationTitle("Hội thoại AI")
        .task {
            if let id = DebugArgs.value("--open"), let s = Scenario.all.first(where: { $0.id == id }), ExampleWriter.available { start(s) }
        }
    }

    private var picker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Nói chuyện với AI chạy ngay trên máy — không cần mạng. Nói qua micro hoặc gõ; mỗi câu của bạn được sửa lỗi và gợi ý cách nói tự nhiên hơn.",
                              systemImage: "sparkles")
                            .foregroundStyle(.secondary)
                        HStack {
                            Text("Trình độ").foregroundStyle(.secondary)
                            Picker("Trình độ", selection: $level) {
                                ForEach(CEFR.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(maxWidth: 260)
                        }
                    }
                }
                Text("Chọn tình huống").font(.title3.weight(.semibold))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14)], spacing: 14) {
                    ForEach(Scenario.all) { s in
                        Button { start(s) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Image(systemName: s.symbol).font(.title2).foregroundStyle(Color.parley.gradient)
                                Text(s.title).font(.headline)
                                Text(s.goal).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
                            .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
                            .contentShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func start(_ s: Scenario) {
        withAnimation(.smooth) { model = ConversationModel(scenario: s, level: level, activity: activity) }
    }
}

/// Shown instead of AI features when Apple Intelligence is off or unsupported (ADR 0001: no cloud fallback).
struct AIUnavailableView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Cần bật Apple Intelligence", systemImage: "sparkles")
        } description: {
            Text("Tính năng này dùng AI chạy ngay trên máy (không gửi dữ liệu ra ngoài). Bật trong System Settings → Apple Intelligence & Siri, đợi tải xong mô hình rồi mở lại Parley.")
        } actions: {
            Button("Mở cài đặt Apple Intelligence") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")!)
            }
            .buttonStyle(.glassProminent)
        }
    }
}

struct ConversationSession: View {
    let model: ConversationModel
    let vocab: VocabStore
    let onExit: () -> Void
    @AppStorage("conversationSpeak") private var speakReplies = true
    @State private var draft = ""
    @State private var mic = MicCheck()
    @State private var finished = false
    @State private var saved: Set<String> = []
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if finished {
                summary
            } else {
                chat
                Divider()
                composer
            }
        }
        .onAppear { if speakReplies, model.learnerTurns == 0 { say(model.scenario.opener) } }
        .onDisappear { Task { _ = await mic.stop() } }
        .task {
            if let t = DebugArgs.value("--say") { await send(t, spoken: false) } // screenshots of a corrected turn
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { finished ? onExit() : withAnimation(.smooth) { finished = true } } label: {
                Label(finished ? "Đóng" : "Kết thúc", systemImage: "xmark")
            }
            .buttonStyle(.glass)
            .keyboardShortcut(.cancelAction)
            Image(systemName: model.scenario.symbol).foregroundStyle(Color.parley).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.scenario.title).font(.headline)
                Text("\(model.level.rawValue) · \(model.scenario.goal)").font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Toggle(isOn: $speakReplies) { Label("Đọc câu trả lời", systemImage: "speaker.wave.2") }
                .toggleStyle(.button)
                .help("Tự đọc câu trả lời của AI")
        }
        .padding(16)
    }

    private var chat: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(model.lines) { line in
                        bubble(line).id(line.id)
                    }
                    if model.thinking {
                        Label("Đang nghĩ…", systemImage: "ellipsis.bubble").foregroundStyle(.secondary).symbolEffect(.pulse).id("thinking")
                    }
                    if let e = model.error {
                        Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).id("error")
                    }
                }
                .padding(20)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: model.lines.count) { withAnimation { proxy.scrollTo(model.lines.last?.id, anchor: .bottom) } }
            .onChange(of: model.thinking) { if model.thinking { withAnimation { proxy.scrollTo("thinking", anchor: .bottom) } } }
        }
    }

    @ViewBuilder private func bubble(_ line: ChatLine) -> some View {
        if line.who == .ai {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles").foregroundStyle(Color.parley).frame(width: 20).padding(.top, 10).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(line.text).textSelection(.enabled)
                        .padding(12)
                        .background(Color.parley.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Button { say(line.text) } label: { Label("Nghe", systemImage: "speaker.wave.2") }
                        .buttonStyle(.borderless).font(.caption)
                }
                Spacer(minLength: 60)
            }
        } else {
            VStack(alignment: .trailing, spacing: 8) {
                HStack {
                    Spacer(minLength: 60)
                    Label { Text(line.text).textSelection(.enabled) } icon: {
                        Image(systemName: line.spoken ? "mic.fill" : "keyboard").foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                feedback(line)
            }
        }
    }

    private func feedback(_ line: ChatLine) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let c = line.corrected {
                Label { DiffText(tokens: WordDiff.diff(expected: c, typed: line.text)) } icon: {
                    Image(systemName: "pencil.circle.fill").foregroundStyle(.orange)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Câu sửa: \(c)")
            } else {
                Label("Câu của bạn đúng ngữ pháp", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }
            if let n = line.natural {
                HStack(alignment: .firstTextBaseline) {
                    Label { Text("Tự nhiên hơn: \(Text(n).italic())") } icon: {
                        Image(systemName: "lightbulb.fill").foregroundStyle(.yellow)
                    }
                    Spacer(minLength: 8)
                    Button { say(n) } label: { Image(systemName: "speaker.wave.2") }
                        .buttonStyle(.borderless).help("Nghe câu gợi ý").accessibilityLabel("Nghe câu gợi ý")
                    Button { Task { await save(n) } } label: {
                        Label(saved.contains(n) ? "Đã lưu" : "Lưu cụm từ", systemImage: saved.contains(n) ? "checkmark" : "plus")
                    }
                    .buttonStyle(.borderless)
                    .disabled(saved.contains(n) || vocab.contains(n))
                }
            }
            if let t = line.tip { Text(t).font(.callout).foregroundStyle(.secondary) }
        }
        .font(.callout)
        .padding(12)
        .frame(maxWidth: 620, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let e = mic.error { Label(e, systemImage: "mic.slash").font(.caption).foregroundStyle(.orange) }
            HStack(spacing: 10) {
                Button {
                    Task { await toggleMic() }
                } label: {
                    Image(systemName: mic.listening ? "stop.circle.fill" : "mic.fill").font(.title2).frame(width: 36, height: 36)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(mic.listening ? .red : .parley)
                .disabled(model.thinking)
                .help(mic.listening ? "Dừng và gửi" : "Nói câu trả lời")
                .accessibilityLabel(mic.listening ? "Dừng và gửi" : "Nói câu trả lời")
                TextField(mic.listening ? "Đang nghe…" : "Gõ câu trả lời bằng tiếng Anh…", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .focused($focused)
                    .disabled(model.thinking || mic.listening)
                    .onSubmit { Task { await send(draft, spoken: false) } }
                Button("Gửi") { Task { await send(draft, spoken: false) } }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.thinking || Coach.clean(draft) == nil)
            }
        }
        .padding(16)
        .frame(maxWidth: 820)
        .frame(maxWidth: .infinity)
        .onAppear { focused = true }
    }

    private var summary: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    StatTile(value: model.learnerTurns, title: "lượt bạn nói", symbol: "bubble.left.and.bubble.right", color: .parley)
                    StatTile(value: model.corrections.count, title: "câu được sửa", symbol: "pencil.circle", color: .orange)
                    StatTile(value: saved.count, title: "cụm từ đã lưu", symbol: "plus.circle", color: .green)
                }
                if model.corrections.isEmpty {
                    Label(model.learnerTurns == 0 ? "Bạn chưa nói câu nào." : "Không có lỗi nào — tuyệt vời!", systemImage: "hand.thumbsup.fill")
                        .font(.title3).foregroundStyle(.secondary)
                } else {
                    Text("Các câu cần nhớ").font(.title3.weight(.semibold))
                    ForEach(model.corrections) { l in
                        Card {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(l.text).strikethrough().foregroundStyle(.secondary)
                                Text(l.corrected ?? "").font(.body.weight(.medium))
                                if let t = l.tip { Text(t).font(.callout).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                Button { onExit() } label: { Label("Xong", systemImage: "checkmark") }
                    .buttonStyle(.glassProminent).controlSize(.large).keyboardShortcut(.defaultAction)
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func send(_ text: String, spoken: Bool) async {
        guard Coach.clean(text) != nil, !model.thinking else { return }
        draft = ""
        if let reply = await model.send(text, spoken: spoken) {
            if speakReplies { say(reply) }
        } else {
            draft = text // keep what the learner wrote so it can be resent
        }
        focused = true
    }

    private func toggleMic() async {
        if mic.listening {
            let heard = await mic.stop()
            if Coach.clean(heard) == nil {
                mic.error = "Chưa nghe thấy gì — kiểm tra micro rồi thử lại."
            } else {
                await send(heard, spoken: true)
            }
        } else {
            mic.error = nil
            Speaker.stop()
            await mic.start(language: "en_US")
        }
    }

    private func say(_ text: String) { Speaker.speak(text, language: Locale.Language(identifier: "en-US")) }

    private func save(_ phrase: String) async {
        let en = Locale.Language(identifier: "en"), vi = Locale.Language(identifier: "vi")
        let meaning = await Translator.translate(phrase, from: en, to: vi) ?? ""
        vocab.add(VocabItem(term: phrase, meaning: meaning, termLanguage: "en-US", meaningLanguage: "vi", ipa: nil,
                            example: phrase, exampleTranslation: meaning, session: nil))
        saved.insert(phrase)
    }
}

// MARK: - `make ai-eval`

/// Known learner sentences → does the on-device coach fix the planted mistake and leave correct sentences alone?
enum AIEval {
    struct Case { let text: String; let mustContain: String? } // nil = sentence is correct, expect no correction

    static let cases: [Case] = [
        Case(text: "Yesterday I fix the login bug and write some tests.", mustContain: "fixed"),
        Case(text: "She don't agree with the new deadline.", mustContain: "doesn't"),
        Case(text: "I have finished the report yesterday.", mustContain: "finished the report yesterday"),
        Case(text: "We discussed about the budget in the meeting.", mustContain: "discussed the budget"),
        Case(text: "Can you explain me how the cache works?", mustContain: "explain to me"),
        Case(text: "I am working here since 2020.", mustContain: "have been working"),
        Case(text: "I finished the API yesterday and today I will write the tests.", mustContain: nil),
        Case(text: "Could we move the release to next Tuesday?", mustContain: nil),
    ]

    /// Prints one line per case plus hit rate and p50 latency; true when ≥ 60 % (ADR 0001) and p50 < 8 s (spec).
    @MainActor static func run() async -> Bool {
        guard ExampleWriter.available else { print("ai-eval: Apple Intelligence not available"); return false }
        var hits = 0
        var times: [Double] = []
        for c in cases {
            let session = LanguageModelSession(instructions: Coach.instructions(Scenario.all[0], .b1))
            let t0 = Date()
            let turn = try? await session.respond(to: "You said: \"What did you work on yesterday?\"\nLearner: \"\(c.text)\"",
                                                  generating: CoachTurn.self).content
            times.append(Date().timeIntervalSince(t0))
            let corrected = turn?.corrected ?? ""
            let fixed = Coach.hasMistake(original: c.text, corrected: corrected)
            let ok = c.mustContain.map { fixed && corrected.lowercased().contains($0) } ?? !fixed
            if ok { hits += 1 }
            print(String(format: "  %@ %.1fs  %@ → %@", ok ? "✔" : "✘", times.last!, c.text, corrected))
        }
        let p50 = times.sorted()[times.count / 2]
        let rate = Double(hits) / Double(cases.count)
        print(String(format: "ai-eval conversation: %d/%d (%.0f%%), p50 %.1fs", hits, cases.count, rate * 100, p50))
        return rate >= 0.6 && p50 < 8
    }
}
