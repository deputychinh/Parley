import AVFoundation
import NaturalLanguage
import SwiftUI

// MARK: - Modes & checking

enum PracticeMode: String, CaseIterable, Identifiable {
    case mix, flashcard, choice, listen, recall, cloze, speak
    var id: String { rawValue }

    var title: String {
        switch self {
        case .mix: "Thử thách tổng hợp"
        case .flashcard: "Thẻ ghi nhớ"
        case .choice: "Chọn nghĩa đúng"
        case .listen: "Nghe & viết"
        case .recall: "Nhớ từ theo nghĩa"
        case .cloze: "Điền vào câu"
        case .speak: "Luyện phát âm"
        }
    }
    var subtitle: String {
        switch self {
        case .mix: "Game trộn mọi cách học: chọn nghĩa, nghe & viết, nhớ từ, điền câu, phát âm"
        case .flashcard: "Xem từ, lật thẻ để kiểm tra nghĩa và cách dùng"
        case .choice: "Chọn nghĩa đúng trong 4 đáp án (cần ít nhất 4 từ)"
        case .listen: "Nghe đọc rồi gõ lại đúng chính tả"
        case .recall: "Thấy nghĩa, gõ ra từ"
        case .cloze: "Dùng từ đúng chỗ trong câu thật bạn đã nghe"
        case .speak: "Đọc to, máy chấm xem có nghe ra đúng từ không"
        }
    }
    var symbol: String {
        switch self {
        case .mix: "gamecontroller.fill"
        case .flashcard: "rectangle.on.rectangle.angled"
        case .choice: "list.bullet.rectangle"
        case .listen: "ear"
        case .recall: "character.cursor.ibeam"
        case .cloze: "text.insert"
        case .speak: "waveform.and.mic"
        }
    }
    var typed: Bool { self == .listen || self == .recall || self == .cloze }
}

enum Answer {
    /// Ignore case, punctuation and extra spaces when comparing typed answers.
    static func normalize(_ s: String) -> String {
        s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'’")).inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func matches(_ answer: String, _ expected: String) -> Bool {
        let a = normalize(answer)
        return !a.isEmpty && a == normalize(expected)
    }

    /// Share of the expected words that speech recognition heard (pronunciation check).
    static func score(heard: String, expected: String) -> Double {
        let want = normalize(expected).split(separator: " ")
        guard !want.isEmpty else { return 0 }
        var got = normalize(heard).split(separator: " ")
        var hits = 0
        for w in want { if let i = got.firstIndex(of: w) { hits += 1; got.remove(at: i) } }
        return Double(hits) / Double(want.count)
    }

    /// The example sentence with the term blanked out; nil when the term isn't in it.
    static func cloze(_ sentence: String, _ term: String) -> String? {
        guard !term.isEmpty, let r = sentence.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) else { return nil }
        return sentence.replacingCharacters(in: r, with: "＿＿＿＿")
    }

    /// "he____" style hint revealing `shown` letters.
    static func hint(_ term: String, shown: Int) -> String {
        var n = 0
        return String(term.map { c -> Character in
            guard c.isLetter else { return c }
            n += 1
            return n <= shown ? c : "_"
        })
    }
}

enum WordInfo {
    /// Part of speech of `term` as used in `sentence` (offline NaturalLanguage), in Vietnamese.
    static func partOfSpeech(_ term: String, in sentence: String) -> String? {
        if term.split(separator: " ").count > 1 { return "cụm từ" }
        let text = sentence.isEmpty ? term : sentence
        guard let r = text.range(of: term, options: .caseInsensitive) else { return nil }
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        let (tag, _) = tagger.tag(at: r.lowerBound, unit: .word, scheme: .lexicalClass)
        return tag.flatMap { names[$0] }
    }

    private static let names: [NLTag: String] = [
        .noun: "danh từ", .verb: "động từ", .adjective: "tính từ", .adverb: "trạng từ", .pronoun: "đại từ",
        .preposition: "giới từ", .conjunction: "liên từ", .determiner: "từ hạn định", .interjection: "thán từ",
        .number: "số từ", .particle: "tiểu từ", .idiom: "thành ngữ",
    ]
}

// MARK: - Home

struct PracticeView: View {
    let store: VocabStore
    @State private var session: PracticeSessionInfo?
    @AppStorage("bestScore") private var bestScore = 0

    var body: some View {
        Group {
            if let session {
                PracticeSession(info: session, store: store, onReplay: { start(session.mode) }) { withAnimation(.smooth) { self.session = nil } }
                    .id(session.started)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if store.items.isEmpty {
                ContentUnavailableView {
                    Label("Chưa có từ để học", systemImage: "graduationcap")
                } description: {
                    Text("Trong lúc phiên dịch, bôi đen một từ rồi bấm “Thêm vào từ vựng”. Các từ đó sẽ xuất hiện ở đây để luyện.")
                }
            } else {
                home
            }
        }
        .navigationTitle("Học tập")
        .problemBanner(store.problem)
        .task { if let m = DebugArgs.value("--open").flatMap(PracticeMode.init(rawValue:)), !store.items.isEmpty { start(m) } }
    }

    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    StatTile(value: store.dueCount, title: "Cần ôn hôm nay", symbol: "clock.badge.exclamationmark", color: .orange)
                    StatTile(value: store.learning, title: "Đang học", symbol: "book", color: .parley)
                    StatTile(value: store.items.count - store.learning, title: "Đã thuộc", symbol: "checkmark.seal", color: .green)
                }
                GameHero(count: min(pool(for: .mix).count, 20), best: bestScore) { start(.mix) }
                Text("Hoặc luyện từng kỹ năng").font(.title3.weight(.semibold))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 14)], spacing: 14) {
                    ForEach(PracticeMode.allCases.filter { $0 != .mix }) { mode in
                        let count = pool(for: mode).count
                        ModeCard(mode: mode, count: count) { start(mode) }
                            .disabled(count == 0)
                    }
                }
                Label("Mỗi buổi tối đa 15 từ, ưu tiên từ đến hạn ôn. Trả lời đúng thì từ được hỏi thưa dần (1, 3, 7, 14, 30, 60, 120 ngày) — kể cả từ đã thuộc vẫn được ôn lại để không quên; sai thì hỏi lại ngay trong buổi.",
                      systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    /// Due words first; if nothing is due, everything still being learned; then everything.
    private func pool(for mode: PracticeMode) -> [VocabItem] {
        if mode == .choice, store.items.count < 4 { return [] } // needs 3 wrong options
        if mode == .mix { return store.items.filter(\.isDue).shuffled() + store.items.filter { !$0.isDue }.shuffled() }
        let usable = store.items.filter { mode != .cloze || Answer.cloze($0.example, $0.term) != nil }
        let due = usable.filter(\.isDue)
        if !due.isEmpty { return due }
        let learning = usable.filter { !$0.mastered }
        return learning.isEmpty ? usable : learning
    }

    private func start(_ mode: PracticeMode) {
        withAnimation(.smooth) {
            let items = mode == .mix ? Array(pool(for: mode).prefix(20)).shuffled() : Array(pool(for: mode).shuffled().prefix(15))
            session = PracticeSessionInfo(mode: mode, items: items)
        }
    }
}

struct PracticeSessionInfo {
    let mode: PracticeMode
    let items: [VocabItem]
    let started = Date()
}

struct StatTile: View {
    let value: Int
    let title: String
    let symbol: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title2).foregroundStyle(color.gradient).frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(value)").font(.title.weight(.bold)).monospacedDigit().contentTransition(.numericText())
                Text(title).font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}

struct ModeCard: View {
    let mode: PracticeMode
    let count: Int
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: mode.symbol)
                    .font(.title)
                    .foregroundStyle(Color.parley.gradient)
                    .symbolEffect(.bounce, value: hover)
                Text(mode.title).font(.headline)
                Text(mode.subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(count == 0 ? "Chưa có từ phù hợp" : "\(count) từ · Bắt đầu →")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(count == 0 ? Color.secondary : Color.parley)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
            .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(hover ? Color.parley.opacity(0.6) : Color.primary.opacity(0.08), lineWidth: hover ? 1.5 : 1))
            .shadow(color: .black.opacity(hover ? 0.12 : 0.05), radius: hover ? 14 : 8, y: hover ? 6 : 3)
            .scaleEffect(hover ? 1.015 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.snappy) { hover = h } }
    }
}

// MARK: - Session

struct PracticeSession: View {
    let mode: PracticeMode
    let store: VocabStore
    let onReplay: () -> Void
    let onExit: () -> Void
    @State private var items: [VocabItem]
    @State private var kinds: [PracticeMode]   // exercise per card (varies only in .mix)
    @State private var options: [[String]]     // multiple-choice answers per card
    @State private var chosen: String?
    // game (.mix)
    @State private var lives = 3
    @State private var combo = 0
    @State private var maxCombo = 0
    @State private var score = 0
    @State private var shakes = 0
    @State private var newRecord = false
    @AppStorage("bestScore") private var bestScore = 0
    @State private var index = 0
    @State private var right = 0
    @State private var done = 0
    @State private var flipped = false
    @State private var answer = ""
    @State private var result: Bool?      // nil until this card is answered
    @State private var hint = 0
    @State private var requeued: Set<UUID> = []
    @State private var mic = MicCheck()
    @FocusState private var focused: Bool

    init(info: PracticeSessionInfo, store: VocabStore, onReplay: @escaping () -> Void, onExit: @escaping () -> Void) {
        mode = info.mode
        self.store = store
        self.onReplay = onReplay
        self.onExit = onExit
        let kinds = info.items.map { Self.kind(for: $0, mode: info.mode, all: store.items) }
        _items = State(initialValue: info.items)
        _kinds = State(initialValue: kinds)
        _options = State(initialValue: zip(info.items, kinds).map { $1 == .choice ? Self.choices(for: $0, all: store.items) : [] })
    }

    /// In the game, each card gets a random exercise among those that fit the word.
    static func kind(for item: VocabItem, mode: PracticeMode, all: [VocabItem]) -> PracticeMode {
        guard mode == .mix else { return mode }
        var pick: [PracticeMode] = [.listen, .recall, .speak]
        if all.count >= 4 { pick += [.choice, .choice] } // quick rounds keep the pace up
        if Answer.cloze(item.example, item.term) != nil { pick.append(.cloze) }
        return pick.randomElement()!
    }

    static func choices(for item: VocabItem, all: [VocabItem]) -> [String] {
        let wrong = Set(all.map(\.meaning)).subtracting([item.meaning]).shuffled().prefix(3)
        return ([item.meaning] + wrong).shuffled()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button { onExit() } label: { Label("Kết thúc", systemImage: "xmark") }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)
                if mode == .mix { GameHUD(lives: lives, combo: combo, score: score) } else { Label(mode.title, systemImage: mode.symbol).font(.headline) }
                ProgressView(value: Double(min(index, items.count)), total: Double(max(items.count, 1)))
                    .tint(.parley)
                Text("\(min(index + 1, items.count))/\(items.count)").monospacedDigit().foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)

            ScrollView {
                Group {
                    if index < items.count {
                        card(items[index])
                            .id(index)
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                    removal: .move(edge: .leading).combined(with: .opacity)))
                    } else {
                        summary
                    }
                }
                .frame(maxWidth: 680)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
        }
        .animation(.smooth(duration: 0.35), value: index)
        .task(id: index) {
            focused = true
            guard index < items.count, kinds[index] == .listen else { return }
            try? await Task.sleep(for: .milliseconds(350))
            speak(items[index])
        }
    }

    // MARK: Card

    @ViewBuilder private func card(_ item: VocabItem) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            let kind = kinds[index]
            switch kind {
            case .flashcard, .mix: flashcard(item)
            case .choice: choicePrompt(item, options[index])
            case .listen: listenPrompt(item)
            case .recall: recallPrompt(item)
            case .cloze: clozePrompt(item)
            case .speak: speakPrompt(item)
            }
            if kind.typed { typedAnswer(item) }
            if let result, kind != .flashcard {
                Feedback(item: item, correct: result, attempt: kind == .speak ? (mic.heard ?? "") : kind == .choice ? (chosen ?? "") : answer)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                HStack {
                    Spacer()
                    Button { next() } label: { Label("Tiếp", systemImage: "arrow.right") }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                        .keyboardShortcut(kind.typed ? .init("n", modifiers: .command) : .defaultAction)
                        .help(kind.typed ? "Tiếp (↩ hoặc ⌘N)" : "Tiếp (↩)")
                }
            }
        }
        .padding(28)
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
        .modifier(Shake(shakes: CGFloat(shakes)))
        .animation(.spring(duration: 0.4), value: result)
    }

    private func choicePrompt(_ item: VocabItem, _ opts: [String]) -> some View {
        VStack(spacing: 16) {
            Text(item.term).font(.system(size: 36, weight: .bold)).multilineTextAlignment(.center)
            if let ipa = item.ipa { Text(ipa).font(.title3).foregroundStyle(.secondary) }
            SpeakButton { speak(item) }
            Text("Chọn nghĩa đúng").foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                ForEach(Array(opts.enumerated()), id: \.offset) { i, opt in
                    let tint: Color = result == nil ? .parley : opt == item.meaning ? .green : opt == chosen ? .red : .secondary
                    Button { choose(item, opt) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(i + 1)").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                            Text(opt).font(.body.weight(.medium)).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            if result != nil, opt == item.meaning { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                            if result == false, opt == chosen { Image(systemName: "xmark.circle.fill").foregroundStyle(.red) }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                        .background(tint.opacity(result == nil ? 0.06 : 0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tint.opacity(0.35)))
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(result != nil)
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [])
                }
            }
            Text("Phím tắt: 1–4").font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func flashcard(_ item: VocabItem) -> some View {
        VStack(spacing: 20) {
            ZStack {
                VStack(spacing: 10) {
                    Text(item.term).font(.system(size: 40, weight: .bold)).multilineTextAlignment(.center)
                    if let ipa = item.ipa { Text(ipa).font(.title3).foregroundStyle(.secondary) }
                    SpeakButton { speak(item) }
                }
                .opacity(flipped ? 0 : 1)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(item.term).font(.title.weight(.bold))
                        if let ipa = item.ipa { Text(ipa).foregroundStyle(.secondary) }
                        Spacer()
                        SpeakButton { speak(item) }
                    }
                    Text(item.meaning).font(.title2)
                    Usage(item: item)
                }
                .opacity(flipped ? 1 : 0)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            }
            .frame(maxWidth: .infinity, minHeight: 220)
            .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
            .animation(.spring(duration: 0.55, bounce: 0.2), value: flipped)
            .contentShape(Rectangle())
            .onTapGesture { flipped.toggle() }

            if flipped {
                HStack(spacing: 14) {
                    Button { rate(item, false) } label: { Label("Chưa nhớ", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity) }
                        .buttonStyle(.glass).tint(.red).keyboardShortcut("1", modifiers: [])
                    Button { rate(item, true) } label: { Label("Đã nhớ", systemImage: "checkmark").frame(maxWidth: .infinity) }
                        .buttonStyle(.glassProminent).tint(.green).keyboardShortcut("2", modifiers: [])
                }
                .controlSize(.large)
                Text("Phím tắt: 1 = chưa nhớ · 2 = đã nhớ").font(.caption).foregroundStyle(.tertiary).frame(maxWidth: .infinity)
            } else {
                Button { flipped = true } label: { Label("Lật thẻ", systemImage: "arrow.trianglehead.2.clockwise.rotate.90").frame(maxWidth: .infinity) }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.space, modifiers: [])
                Text("Phím tắt: Space").font(.caption).foregroundStyle(.tertiary).frame(maxWidth: .infinity)
            }
        }
    }

    private func listenPrompt(_ item: VocabItem) -> some View {
        VStack(spacing: 14) {
            Button { speak(item) } label: {
                Image(systemName: "speaker.wave.3.fill").font(.system(size: 40)).frame(width: 96, height: 96)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .help("Nghe lại (⌘P)")
            .keyboardShortcut("p", modifiers: .command)
            Text("Nghe và gõ lại từ bạn nghe được").font(.title3).foregroundStyle(.secondary)
            Text("Nghĩa: \(item.meaning)").font(.callout).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func recallPrompt(_ item: VocabItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Từ nào có nghĩa là").font(.callout).foregroundStyle(.secondary)
            Text(item.meaning).font(.system(size: 32, weight: .bold))
            if !item.exampleTranslation.isEmpty {
                Text("“\(item.exampleTranslation)”").font(.callout).foregroundStyle(.secondary).italic()
            }
            hintRow(item)
        }
    }

    private func clozePrompt(_ item: VocabItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Điền từ còn thiếu").font(.callout).foregroundStyle(.secondary)
            Text(Answer.cloze(item.example, item.term) ?? item.example).font(.title2.weight(.semibold))
            Text(item.exampleTranslation).font(.callout).foregroundStyle(.secondary)
            Text("Gợi ý nghĩa: \(item.meaning)").font(.callout).foregroundStyle(.tertiary)
            hintRow(item)
        }
    }

    private func speakPrompt(_ item: VocabItem) -> some View {
        VStack(spacing: 16) {
            Text(item.term).font(.system(size: 40, weight: .bold)).multilineTextAlignment(.center)
            if let ipa = item.ipa { Text(ipa).font(.title3).foregroundStyle(.secondary) }
            HStack(spacing: 18) {
                SpeakButton { speak(item) }
                Button { Task { await toggleMic(item) } } label: {
                    Image(systemName: mic.listening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 30))
                        .symbolEffect(.pulse, isActive: mic.listening)
                        .frame(width: 80, height: 80)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(mic.listening ? .red : .parley)
                .disabled(result != nil)
                .keyboardShortcut(.space, modifiers: [])
            }
            Text(mic.listening ? "Đang nghe… đọc to từ trên (tự dừng sau 4 giây)" : (result == nil ? "Bấm micro (Space) rồi đọc to từ trên" : ""))
                .foregroundStyle(.secondary)
            if let error = mic.error { Text(error).font(.callout).foregroundStyle(.red) }
        }
        .frame(maxWidth: .infinity)
    }

    private func hintRow(_ item: VocabItem) -> some View {
        HStack {
            if hint > 0 { Text(Answer.hint(item.term, shown: hint)).font(.title3.monospaced()).kerning(2) }
            Spacer()
            if result == nil {
                Button { hint += 1 } label: { Label("Gợi ý", systemImage: "lightbulb") }
                    .buttonStyle(.glass)
                    .disabled(hint >= item.term.count)
            }
        }
    }

    private func typedAnswer(_ item: VocabItem) -> some View {
        HStack(spacing: 12) {
            TextField("Gõ câu trả lời rồi nhấn ↩", text: $answer)
                .textFieldStyle(.plain)
                .font(.title2)
                .padding(14)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(result.map { $0 ? Color.green : Color.red } ?? Color.parley.opacity(focused ? 0.6 : 0.15), lineWidth: 1.5))
                .focused($focused)
                .disabled(result != nil)
                .onSubmit { check(item) }
            if result == nil {
                Button { check(item) } label: { Text("Kiểm tra") }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .disabled(answer.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: Summary

    @ViewBuilder private var summary: some View {
        if mode == .mix { gameSummary } else { lessonSummary }
    }

    private var gameSummary: some View {
        VStack(spacing: 16) {
            Image(systemName: lives == 0 ? "heart.slash.fill" : "trophy.fill")
                .font(.system(size: 64))
                .foregroundStyle(lives == 0 ? AnyShapeStyle(Color.red.gradient) : AnyShapeStyle(Color.parley.gradient))
                .symbolEffect(.bounce, options: .repeat(2))
            Text(lives == 0 ? "Hết mạng!" : "Chiến thắng!").font(.largeTitle.weight(.bold))
            Text("\(score) điểm")
                .font(.system(size: 52, weight: .heavy))
                .foregroundStyle(LinearGradient(colors: [.parley, .pink], startPoint: .leading, endPoint: .trailing))
            if newRecord {
                Label("Kỷ lục mới!", systemImage: "crown.fill").font(.title3.weight(.bold)).foregroundStyle(.orange)
                    .symbolEffect(.bounce, options: .repeat(3))
            } else {
                Text("Kỷ lục: \(bestScore) điểm").foregroundStyle(.secondary)
            }
            HStack(spacing: 28) {
                Label("Đúng \(right)/\(done)", systemImage: "checkmark.circle")
                Label("Combo cao nhất \(maxCombo)", systemImage: "flame.fill")
            }
            .font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button { onReplay() } label: { Label("Chơi lại", systemImage: "arrow.clockwise") }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                Button { onExit() } label: { Label("Xong", systemImage: "checkmark") }
                    .buttonStyle(.glass)
            }
            .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
        .onAppear {
            if score > bestScore { bestScore = score; newRecord = true }
        }
    }

    private var lessonSummary: some View {
        VStack(spacing: 18) {
            Image(systemName: right == done ? "trophy.fill" : "checkmark.seal.fill")
                .font(.system(size: 68))
                .foregroundStyle(Color.parley.gradient)
                .symbolEffect(.bounce, options: .repeat(2))
            Text("Hoàn thành!").font(.largeTitle.weight(.bold))
            Text("Đúng \(right)/\(done) lượt").font(.title3).foregroundStyle(.secondary)
            Text(store.dueCount > 0 ? "Còn \(store.dueCount) từ cần ôn hôm nay." : "Bạn đã ôn hết từ của hôm nay 🎉")
                .foregroundStyle(.secondary)
            Button { onExit() } label: { Label("Xong", systemImage: "checkmark") }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
    }

    // MARK: Actions

    private func speak(_ item: VocabItem) {
        Speaker.speak(item.term, language: Locale.Language(identifier: item.termLanguage))
    }

    private func check(_ item: VocabItem) {
        guard result == nil else { return next() } // ↩ on a checked card moves on
        guard !answer.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        record(item, Answer.matches(answer, item.term))
        if result == true { speak(item) } // reinforce the right pronunciation
    }

    private func choose(_ item: VocabItem, _ option: String) {
        guard result == nil else { return }
        chosen = option
        record(item, option == item.meaning)
        if result == true { speak(item) }
    }

    private func rate(_ item: VocabItem, _ ok: Bool) {
        record(item, ok)
        next()
    }

    private func toggleMic(_ item: VocabItem) async {
        if mic.listening { return await finishSpeaking(item) }
        await mic.start(language: item.termLanguage)
        try? await Task.sleep(for: .seconds(4))
        if mic.listening { await finishSpeaking(item) }
    }

    private func finishSpeaking(_ item: VocabItem) async {
        let heard = await mic.stop()
        guard result == nil else { return }
        record(item, Answer.score(heard: heard, expected: item.term) >= 0.8)
    }

    private func record(_ item: VocabItem, _ ok: Bool) {
        result = ok
        done += 1
        if ok { right += 1 }
        store.review(item.id, correct: ok, spoken: kinds.indices.contains(index) && kinds[index] == .speak)
        if mode == .mix {
            withAnimation(.snappy) {
                if ok {
                    combo += 1
                    maxCombo = max(maxCombo, combo)
                    score += 10 * min(combo, 5) // combo multiplier, capped at ×5
                } else {
                    combo = 0
                    lives -= 1
                }
            }
            if !ok { withAnimation(.linear(duration: 0.4)) { shakes += 1 } }
        }
        // Missed words come back once more at the end of this session.
        if !ok, !requeued.contains(item.id) {
            requeued.insert(item.id)
            items.append(item)
            let k = Self.kind(for: item, mode: mode, all: store.items)
            kinds.append(k)
            options.append(k == .choice ? Self.choices(for: item, all: store.items) : [])
        }
    }

    private func next() {
        index = mode == .mix && lives == 0 ? items.count : index + 1 // out of lives → game over screen
        answer = ""
        result = nil
        flipped = false
        hint = 0
        chosen = nil
        mic.heard = nil
        mic.error = nil
    }
}

// MARK: - Pieces

struct GameHUD: View {
    let lives: Int
    let combo: Int
    let score: Int

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Image(systemName: i < lives ? "heart.fill" : "heart")
                        .foregroundStyle(i < lives ? Color.red : Color.secondary)
                        .symbolEffect(.bounce, value: lives)
                }
            }
            Label("×\(min(max(combo, 1), 5))", systemImage: "flame.fill")
                .foregroundStyle(combo >= 2 ? Color.orange : Color.secondary)
                .symbolEffect(.bounce, value: combo)
                .help("Combo: đúng liên tiếp \(combo) câu")
            Text("\(score)")
                .font(.title3.weight(.heavy))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(Color.parley)
        }
        .font(.headline)
    }
}

struct GameHero: View {
    let count: Int
    let best: Int
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 20) {
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 46))
                    .symbolEffect(.wiggle, value: hover)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Thử thách tổng hợp").font(.title2.weight(.bold))
                    Text("Trộn mọi cách học trong một game: chọn nghĩa, nghe & viết, nhớ từ, điền câu, phát âm.")
                        .font(.callout).opacity(0.9).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 16) {
                        Label("3 mạng", systemImage: "heart.fill")
                        Label("Combo ×5", systemImage: "flame.fill")
                        Label("Kỷ lục \(best)", systemImage: "trophy.fill")
                    }
                    .font(.callout.weight(.semibold))
                    .padding(.top, 2)
                }
                Spacer(minLength: 8)
                Text(count == 0 ? "Chưa có từ" : "Chơi \(count) từ →").font(.headline)
            }
            .foregroundStyle(.white)
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [Color.parley, Color(red: 0.86, green: 0.34, blue: 0.72)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color.parley.opacity(hover ? 0.45 : 0.25), radius: hover ? 20 : 12, y: hover ? 8 : 5)
            .scaleEffect(hover ? 1.01 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
        .onHover { h in withAnimation(.snappy) { hover = h } }
    }
}

/// Horizontal wobble for a wrong answer; animate by incrementing `shakes`.
struct Shake: GeometryEffect {
    var shakes: CGFloat
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(shakes * .pi * 4), y: 0))
    }
}

struct SpeakButton: View {
    let action: () -> Void
    @State private var bounce = 0

    var body: some View {
        Button { bounce += 1; action() } label: {
            Image(systemName: "speaker.wave.2.fill").font(.title2).symbolEffect(.bounce, value: bounce).frame(width: 44, height: 44)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .help("Nghe phát âm")
    }
}

/// "How to use it": part of speech + the real sentence it was heard in, with its translation.
struct Usage: View {
    let item: VocabItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("CÁCH DÙNG").font(.caption2.weight(.semibold)).foregroundStyle(.secondary).kerning(0.6)
                if let pos = WordInfo.partOfSpeech(item.term, in: item.example) {
                    Text(pos)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Color.parley.opacity(0.15), in: Capsule())
                        .foregroundStyle(Color.parley)
                }
            }
            if !item.example.isEmpty {
                Text(highlighted(item.example, item.term)).font(.body)
                if !item.exampleTranslation.isEmpty { Text(item.exampleTranslation).font(.callout).foregroundStyle(.secondary) }
            } else {
                Text("Chưa có câu ví dụ cho từ này.").font(.callout).foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.parley.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func highlighted(_ s: String, _ term: String) -> AttributedString {
        var a = AttributedString(s)
        if let r = a.range(of: term, options: .caseInsensitive) {
            a[r].foregroundColor = .parley
            a[r].font = .body.bold()
        }
        return a
    }
}

struct Feedback: View {
    let item: VocabItem
    let correct: Bool
    let attempt: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(correct ? "Chính xác!" : "Chưa đúng", systemImage: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(correct ? .green : .red)
                .symbolEffect(.bounce, value: correct)
            if !correct {
                Text(attempt.isEmpty ? "Không nghe thấy gì" : "Bạn: \(attempt)")
                    .strikethrough(!attempt.isEmpty)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(item.term).font(.title2.weight(.bold))
                if let ipa = item.ipa { Text(ipa).foregroundStyle(.secondary) }
                Spacer()
                SpeakButton { Speaker.speak(item.term, language: Locale.Language(identifier: item.termLanguage)) }
            }
            Text(item.meaning).font(.title3)
            Usage(item: item)
        }
        .padding(18)
        .background((correct ? Color.green : Color.red).opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder((correct ? Color.green : Color.red).opacity(0.3)))
    }
}

/// Records the microphone and runs it through on-device speech recognition (pronunciation check).
@Observable @MainActor
final class MicCheck {
    var listening = false
    var stopping = false   // between "stop" and the recognizer's last result: buttons wait
    var heard: String?
    var error: String?
    @ObservationIgnored private var failure: String?
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var transcriber: Transcriber?
    @ObservationIgnored private var collector: Task<String, Never>?

    func start(language: String) async {
        heard = nil
        error = nil
        do {
            let t = try await Transcriber.start(locale: Locale(identifier: language))
            collector = Task {
                var out: [String] = []
                do {
                    for try await r in t.module.results where r.isFinal { out.append(String(r.text.characters)) }
                } catch {
                    await MainActor.run { self.failure = "Nhận dạng giọng nói bị lỗi — thử nói lại." }
                    print("mic:", error)
                }
                return out.joined(separator: " ")
            }
            let engine = AVAudioEngine()
            let input = engine.inputNode
            input.installTap(onBus: 0, bufferSize: 4096, format: input.outputFormat(forBus: 0), block: Self.tap(t))
            try engine.start()
            self.engine = engine
            transcriber = t
            listening = true
        } catch {
            self.error = "Không mở được micro: \(error.localizedDescription)"
        }
    }

    func stop() async -> String {
        guard listening, !stopping else { return heard ?? "" }
        stopping = true
        defer { stopping = false }
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        listening = false
        try? await transcriber?.finish()
        transcriber = nil
        let text = await collector?.value ?? ""
        collector = nil
        heard = text
        if let failure { error = failure; self.failure = nil }
        return text
    }

    /// Built outside the main actor: the tap runs on an audio thread.
    private nonisolated static func tap(_ t: Transcriber) -> AVAudioNodeTapBlock {
        { buffer, _ in t.feed(buffer) }
    }
}
