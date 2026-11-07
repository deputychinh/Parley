import AppKit
import FoundationModels
import Observation
import SwiftUI

// MARK: - Bundled content (Resources/topics.json, grammar.json, wordlist.txt)

struct TopicWord: Codable, Hashable, Identifiable {
    var id: String { term }
    var term: String
    var meaning: String
    var example: String
    var exampleTranslation: String
}

struct Topic: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var symbol: String
    var summary: String
    var group: String   // "it", "general" or "custom"
    var words: [TopicWord]
}

struct GrammarExample: Codable, Hashable { var en: String; var vi: String }
struct GrammarExercise: Codable, Hashable { var prompt: String; var options: [String]; var answer: String; var explain: String }
struct GrammarLesson: Codable, Hashable, Identifiable {
    var id: String
    var level: String?   // CEFR: A1 … C1
    var title: String
    var summary: String
    var when: String
    var form: [String]
    var tips: [String]
    var examples: [GrammarExample]
    var exercises: [GrammarExercise]
}

/// A subtopic is either a hand-written topic (`topic` = id in topics.json) or written by on-device AI on first open (`prompt`).
struct SubtopicRef: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var topic: String?
    var prompt: String?
}

struct Category: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var symbol: String
    var subtopics: [SubtopicRef]
}

enum Library {
    static let topics: [Topic] = load("topics")
    static let categories: [Category] = load("categories")
    static let levels: [(code: String, title: String)] = [("A1", "Cơ bản"), ("A2", "Sơ cấp"), ("B1", "Trung cấp"), ("B2", "Trung cao cấp"), ("C1", "Nâng cao")]
    static let grammar: [GrammarLesson] = load("grammar")
    /// ~8.8k most frequent English words (dictionary words only, no proper nouns), most frequent first.
    static let wordlist: [String] = {
        guard let text = try? String(contentsOf: url("wordlist", "txt"), encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init)
    }()
    static let goalTotal = 10_000

    private static func url(_ name: String, _ ext: String) -> URL {
        Bundle.main.url(forResource: name, withExtension: ext) ?? URL(fileURLWithPath: "Resources/\(name).\(ext)")
    }

    private static func load<T: Decodable>(_ name: String) -> [T] {
        guard let data = try? Data(contentsOf: url(name, "json")) else { return [] }
        do { return try JSONDecoder().decode([T].self, from: data) } catch {
            print("Library: cannot read \(name).json:", error)
            return []
        }
    }
}

// MARK: - On-device AI (Apple Foundation Models): example sentences & custom topics

enum ExampleWriter {
    static var available: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    @Generable struct Sentences {
        @Guide(description: "One example sentence per input word, in the same order as the input")
        var sentences: [String]
    }

    @Generable struct GeneratedWord {
        @Guide(description: "An English word or short phrase")
        var term: String
        @Guide(description: "A natural English sentence of 8 to 14 words that contains the exact term")
        var example: String
    }

    @Generable struct GeneratedTopic {
        @Guide(description: "Short topic title in Vietnamese")
        var title: String
        @Guide(description: "One SF Symbols name that fits the topic, for example airplane or book.fill")
        var symbol: String
        @Guide(description: "Exactly 12 useful English words or short phrases for this topic")
        var words: [GeneratedWord]
    }

    private static let instructions = """
        You write short, natural English example sentences (8 to 14 words) for Vietnamese professionals \
        learning English, many of whom work in IT. Prefer workplace and everyday situations. \
        Every sentence must contain the exact word or phrase it is written for.
        """

    /// term → sentence; only sentences that really contain the term are kept (the cloze exercise needs it).
    static func examples(for words: [String]) async -> [String: String] {
        guard available, !words.isEmpty else { return [:] }
        let session = LanguageModelSession(instructions: instructions)
        guard let r = try? await session.respond(to: "Words: " + words.joined(separator: ", "), generating: Sentences.self) else { return [:] }
        var out: [String: String] = [:]
        for (w, s) in zip(words, r.content.sentences) where s.range(of: w, options: .caseInsensitive) != nil { out[w] = s }
        return out
    }

    static func topic(about subject: String) async throws -> GeneratedTopic {
        let session = LanguageModelSession(instructions: instructions)
        let ask = "Make a vocabulary list for this topic: \(subject). Choose useful intermediate-to-advanced words and short phrases " +
            "that an adult learner may not know yet; avoid very basic words such as team, good, play, eat."
        return try await session.respond(to: ask, generating: GeneratedTopic.self).content
    }
}

// MARK: - Study progress (daily plan, custom topics, grammar scores)

struct DailyCard: Codable, Hashable {
    var meaning: String?
    var example: String?
    var exampleTranslation: String?
}

struct StudyData: Codable {
    var day = ""                        // yyyy-MM-dd of `batch`
    var batch: [String] = []            // today's new words
    var done: [String: Bool] = [:]      // term → true learned (added to practice) / false already known
    var cards: [String: DailyCard] = [:]
    var known: [String] = []            // "Đã biết": counted as known, not practiced
    var streak = 0
    var lastCompleted: String?
    var cursor = 0                      // next position in Library.wordlist
    var customTopics: [Topic] = []
    var grammarBest: [String: Int] = [:]
    var generated: [String: Topic]?     // AI-written subtopics, keyed by SubtopicRef.id (optional: older files lack it)
}

/// Stored in ~/Documents/Parley/study.json.
@Observable @MainActor
final class StudyStore {
    private(set) var data = StudyData()
    var filling = false // meanings / example sentences being prepared
    @ObservationIgnored private let url: URL

    private(set) var problem: String?
    @ObservationIgnored private var writable = true
    @ObservationIgnored private let activity: ActivityStore?

    init(file: URL = Model.dataDir.appending(path: "study.json"), activity: ActivityStore? = nil) {
        url = file
        self.activity = activity
        let loaded = StoreFile.load(StudyData.self, from: url)
        data = loaded.value ?? StudyData()
        writable = loaded.writable
        problem = loaded.problem
    }

    var goal: Int { UserDefaults.standard.object(forKey: "dailyGoal") as? Int ?? 20 }
    var startRank: Int { UserDefaults.standard.object(forKey: "startRank") as? Int ?? 0 }
    var allTopics: [Topic] { Library.topics + data.customTopics }
    var remainingToday: Int { data.batch.count { data.done[$0] == nil } }
    var completedToday: Bool { !data.batch.isEmpty && remainingToday == 0 }

    func knownCount(_ vocab: VocabStore) -> Int { vocab.items.count + data.known.count }

    nonisolated static func day(_ date: Date) -> String { dayFormatter.string(from: date) }
    /// DateFormatter is thread-safe for formatting; creating one per call dominated progress aggregation.
    nonisolated private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// New day → new batch of `goal` words; also breaks the streak if yesterday's goal was missed.
    func refresh(vocab: VocabStore) {
        let today = Self.day(.now)
        if data.day != today {
            let yesterday = Self.day(.now.addingTimeInterval(-86_400))
            if data.lastCompleted != yesterday && data.lastCompleted != today { data.streak = 0 }
            data.day = today
            data.done = [:]
            data.cards = [:]
            data.batch = []
            add(goal, vocab: vocab)
        } else if data.batch.count < goal, !completedToday {
            add(goal - data.batch.count, vocab: vocab) // goal raised during the day
        }
        Task { await fillCards() }
    }

    func add(_ n: Int, vocab: VocabStore) {
        let have = Set(vocab.items.map { $0.term.lowercased() } + data.known.map { $0.lowercased() } + data.batch.map { $0.lowercased() })
        let curated = ["it", "general"].flatMap { g in Library.topics.filter { $0.group == g }.flatMap { $0.words.map(\.term) } }
        let (words, cursor) = Self.pick(count: n, curated: curated, wordlist: Library.wordlist,
                                        cursor: max(data.cursor, startRank), have: have)
        data.batch += words
        data.cursor = cursor
        save()
        Task { await fillCards() }
    }

    /// Curated IT/general words first, then the frequency list from `cursor`, skipping words already known.
    nonisolated static func pick(count: Int, curated: [String], wordlist: [String], cursor: Int, have: Set<String>) -> ([String], Int) {
        var out: [String] = []
        var seen = have
        for w in curated where out.count < count && seen.insert(w.lowercased()).inserted { out.append(w) }
        var c = cursor
        while out.count < count, c < wordlist.count {
            let w = wordlist[c]
            c += 1
            if seen.insert(w.lowercased()).inserted { out.append(w) }
        }
        return (out, c)
    }

    func resolve(_ term: String, learned: Bool, vocab: VocabStore) {
        guard data.done[term] == nil else { return }
        if learned {
            let c = data.cards[term]
            vocab.add(VocabItem(term: term, meaning: c?.meaning ?? "", termLanguage: "en-US", meaningLanguage: "vi",
                                ipa: Pronunciation.ipa(term), example: c?.example ?? "",
                                exampleTranslation: c?.exampleTranslation ?? "", session: nil))
        } else {
            data.known.append(term)
        }
        data.done[term] = learned
        if learned { activity?.log(.newWord) }
        if completedToday, data.lastCompleted != data.day {
            let yesterday = Self.day(.now.addingTimeInterval(-86_400))
            data.streak = data.lastCompleted == yesterday ? data.streak + 1 : 1
            data.lastCompleted = data.day
        }
        save()
    }

    /// Meanings (offline translation) and example sentences (curated, else on-device AI) for today's words.
    func fillCards() async {
        guard !filling else { return }
        filling = true
        defer { filling = false }
        let en = Locale.Language(identifier: "en"), vi = Locale.Language(identifier: "vi")
        let curated = Dictionary(allTopics.flatMap(\.words).map { ($0.term.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
        for term in data.batch where data.cards[term]?.meaning == nil {
            if let w = curated[term.lowercased()] {
                data.cards[term] = DailyCard(meaning: w.meaning, example: w.example, exampleTranslation: w.exampleTranslation)
            } else {
                data.cards[term] = DailyCard(meaning: await Translator.translate(term, from: en, to: vi) ?? "")
            }
        }
        save()
        let missing = data.batch.filter { data.cards[$0]?.example == nil }
        for chunk in stride(from: 0, to: missing.count, by: 10).map({ Array(missing[$0..<min($0 + 10, missing.count)]) }) {
            let sentences = await ExampleWriter.examples(for: chunk)
            for (term, sentence) in sentences {
                data.cards[term]?.example = sentence
                data.cards[term]?.exampleTranslation = await Translator.translate(sentence, from: en, to: vi)
            }
            save()
        }
    }

    func topic(for sub: SubtopicRef) -> Topic? {
        if let id = sub.topic { return Library.topics.first { $0.id == id } }
        return data.generated?[sub.id]
    }

    /// Writes a topic with on-device AI: terms + example sentences, then offline translation to Vietnamese.
    func makeTopic(about subject: String, id: String, title: String?, symbol: String, group: String) async throws -> Topic {
        let g = try await ExampleWriter.topic(about: subject)
        let en = Locale.Language(identifier: "en"), vi = Locale.Language(identifier: "vi")
        var words: [TopicWord] = []
        for w in g.words where w.example.range(of: w.term, options: .caseInsensitive) != nil && !words.contains(where: { $0.term == w.term }) {
            words.append(TopicWord(term: w.term,
                                   meaning: await Translator.translate(w.term, from: en, to: vi) ?? "",
                                   example: w.example,
                                   exampleTranslation: await Translator.translate(w.example, from: en, to: vi) ?? ""))
        }
        guard !words.isEmpty else { throw Err("AI chưa tạo được từ phù hợp, thử lại hoặc diễn đạt chủ đề khác.") }
        let aiSymbol = NSImage(systemSymbolName: g.symbol, accessibilityDescription: nil) == nil ? symbol : g.symbol
        return Topic(id: id, title: title ?? (g.title.isEmpty ? subject : g.title), symbol: title == nil ? aiSymbol : symbol,
                     summary: subject, group: group, words: words)
    }

    func generate(_ sub: SubtopicRef, in category: Category) async throws -> Topic {
        if let t = topic(for: sub) { return t }
        let t = try await makeTopic(about: sub.prompt ?? sub.title, id: sub.id, title: sub.title, symbol: category.symbol, group: category.id)
        var g = data.generated ?? [:]
        g[sub.id] = t
        data.generated = g
        save()
        return t
    }

    /// One answered grammar exercise (XP); the lesson's best score is saved by `recordGrammar` at the end.
    func answerGrammar(correct: Bool) { activity?.log(.grammar(ok: correct)) }

    func recordGrammar(_ id: String, score: Int) {
        data.grammarBest[id] = max(data.grammarBest[id] ?? 0, score)
        save()
    }

    func addTopic(_ topic: Topic) {
        data.customTopics.insert(topic, at: 0)
        save()
    }

    func removeTopic(_ id: String) {
        data.customTopics.removeAll { $0.id == id }
        save()
    }

    private func save() {
        guard writable else { return }
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do { try StoreFile.save(data, to: url, encoder: e) } catch { problem = "Không lưu được kế hoạch học: \(error.localizedDescription)" }
    }
}

// MARK: - Shared bits

func highlightTerm(_ s: String, _ term: String, color: Color = .parley) -> AttributedString {
    var a = AttributedString(s)
    if let r = a.range(of: term, options: .caseInsensitive) {
        a[r].foregroundColor = color
        a[r].inlinePresentationIntent = .stronglyEmphasized
    }
    return a
}

struct Card<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}

struct BackButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) { Label(title, systemImage: "chevron.left") }
            .buttonStyle(.glass)
            .keyboardShortcut(.cancelAction)
    }
}

// MARK: - "Mỗi ngày" (daily new words)

struct DailyView: View {
    let study: StudyStore
    let vocab: VocabStore
    @AppStorage("dailyGoal") private var goal = 20
    @AppStorage("startRank") private var startRank = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                HStack(spacing: 16) {
                    Picker("Mục tiêu", selection: $goal) {
                        ForEach([10, 20, 30, 50], id: \.self) { Text("\($0) từ/ngày").tag($0) }
                    }
                    .frame(maxWidth: 220)
                    Picker("Bắt đầu từ", selection: $startRank) {
                        Text("Từ cơ bản nhất").tag(0)
                        Text("Bỏ qua 1.000 từ dễ nhất").tag(1000)
                        Text("Bỏ qua 2.500 từ dễ nhất").tag(2500)
                        Text("Bỏ qua 4.000 từ dễ nhất").tag(4000)
                    }
                    .frame(maxWidth: 300)
                    .help("Bỏ qua các từ quá phổ biến mà bạn chắc chắn đã biết")
                    Spacer()
                }
                if study.filling {
                    Label(ExampleWriter.available ? "Đang chuẩn bị nghĩa và câu ví dụ (AI trên máy)…" : "Đang chuẩn bị nghĩa…",
                          systemImage: "sparkles")
                        .foregroundStyle(.secondary)
                        .symbolEffect(.pulse)
                }
                if study.completedToday { completeBanner }
                ForEach(study.data.batch, id: \.self) { term in
                    DailyWordCard(term: term, card: study.data.cards[term], state: study.data.done[term]) { learned in
                        withAnimation(.smooth) { study.resolve(term, learned: learned, vocab: vocab) }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Mỗi ngày")
        .problemBanner(study.problem, vocab.problem)
        .task { study.refresh(vocab: vocab) }
        .onChange(of: goal) { study.refresh(vocab: vocab) }
    }

    private var hero: some View {
        let known = study.knownCount(vocab)
        let left = max(0, Library.goalTotal - known)
        let days = left == 0 ? 0 : Int((Double(left) / Double(max(goal, 1))).rounded(.up))
        return HStack(spacing: 24) {
            ZStack {
                Circle().stroke(Color.parley.opacity(0.15), lineWidth: 12)
                Circle().trim(from: 0, to: min(1, Double(known) / Double(Library.goalTotal)))
                    .stroke(Color.parley.gradient, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(known)").font(.title.weight(.heavy)).monospacedDigit().contentTransition(.numericText())
                    Text("/ 10.000").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 120, height: 120)
            .animation(.smooth, value: known)
            VStack(alignment: .leading, spacing: 10) {
                Text("Mục tiêu 10.000 từ").font(.title2.weight(.bold))
                HStack(spacing: 18) {
                    Label("\(study.data.streak) ngày liên tiếp", systemImage: "flame.fill")
                        .foregroundStyle(study.data.streak > 0 ? Color.orange : Color.secondary)
                        .symbolEffect(.bounce, value: study.data.streak)
                    Label("Hôm nay \(study.data.batch.count - study.remainingToday)/\(study.data.batch.count)", systemImage: "calendar")
                }
                .font(.headline)
                Text(days == 0 ? "Bạn đã đạt 10.000 từ! 🎉"
                     : "Còn \(left) từ — khoảng \(days) ngày nữa, đến \(Date.now.addingTimeInterval(Double(days) * 86_400).formatted(.dateTime.month(.wide).year())).")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .background(LinearGradient(colors: [Color.parley.opacity(0.14), Color.pink.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.parley.opacity(0.2)))
    }

    private var completeBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill").font(.largeTitle).foregroundStyle(.green).symbolEffect(.bounce, options: .repeat(2))
            VStack(alignment: .leading, spacing: 4) {
                Text("Xong mục tiêu hôm nay!").font(.title3.weight(.bold))
                Text("Các từ bạn chọn học đã vào Học tập — ôn ngay để nhớ lâu.").foregroundStyle(.secondary)
            }
            Spacer()
            Button { study.add(10, vocab: vocab) } label: { Label("Học thêm 10 từ", systemImage: "plus") }
                .buttonStyle(.glass)
        }
        .padding(18)
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.green.opacity(0.3)))
    }
}

struct DailyWordCard: View {
    let term: String
    let card: DailyCard?
    let state: Bool?   // nil = not decided yet
    let decide: (Bool) -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(term).font(.title2.weight(.bold))
                    if let ipa = Pronunciation.ipa(term) { Text(ipa).foregroundStyle(.secondary) }
                    if let pos = WordInfo.partOfSpeech(term, in: card?.example ?? "") {
                        Text(pos).font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Color.parley.opacity(0.15), in: Capsule()).foregroundStyle(Color.parley)
                    }
                    Spacer()
                    SpeakButton { Speaker.speak(term, language: Locale.Language(identifier: "en-US")) }
                }
                if let meaning = card?.meaning {
                    Text(meaning.isEmpty ? "(chưa dịch được)" : meaning).font(.title3)
                } else {
                    ProgressView().controlSize(.small)
                }
                if let example = card?.example {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(highlightTerm(example, term))
                        if let t = card?.exampleTranslation { Text(t).foregroundStyle(.secondary) }
                    }
                    .font(.callout)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.parley.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                HStack {
                    Spacer()
                    if let state {
                        Label(state ? "Đã thêm vào Học tập" : "Đã biết", systemImage: state ? "graduationcap.fill" : "checkmark")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(state ? Color.parley : .green)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Button { decide(false) } label: { Label("Đã biết", systemImage: "checkmark") }
                            .buttonStyle(.glass)
                        Button { decide(true) } label: { Label("Học từ này", systemImage: "plus") }
                            .buttonStyle(.glassProminent)
                            .disabled(card?.meaning == nil)
                    }
                }
            }
        }
        .opacity(state == nil ? 1 : 0.65)
        .animation(.smooth, value: state)
    }
}

// MARK: - Topics

struct TopicsView: View {
    let study: StudyStore
    let vocab: VocabStore
    @State private var category: Category?
    @State private var open: Topic?
    @State private var generating: String?   // subtopic id being written by AI
    @State private var error: String?
    @State private var subject = ""
    @State private var creating = false

    var body: some View {
        Group {
            if let open {
                TopicDetail(topic: open, study: study, vocab: vocab) { withAnimation(.smooth) { self.open = nil } }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if let category {
                categoryView(category).transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                home.transition(.opacity)
            }
        }
        .navigationTitle(open?.title ?? category?.title ?? "Từ vựng theo chủ đề")
        .task {
            guard let id = DebugArgs.value("--open") else { return }
            category = Library.categories.first { $0.id == id }
            open = Library.topics.first { $0.id == id }
        }
    }

    private func added(_ t: Topic) -> Int { t.words.count { vocab.contains($0.term) } }

    // Level 0: categories + your own topics
    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Danh mục").font(.title3.weight(.semibold))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], spacing: 14) {
                    ForEach(Library.categories) { c in
                        let ready = c.subtopics.compactMap(study.topic(for:))
                        CategoryCard(category: c, ready: ready.count, added: ready.reduce(0) { $0 + added($1) }) {
                            withAnimation(.smooth) { category = c }
                        }
                    }
                }
                Text("Chủ đề của bạn").font(.title3.weight(.semibold)).padding(.top, 6)
                creator
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], spacing: 14) {
                    ForEach(study.data.customTopics) { t in
                        TopicCard(topic: t, added: added(t)) { withAnimation(.smooth) { open = t } }
                            .contextMenu { Button("Xoá chủ đề", systemImage: "trash", role: .destructive) { study.removeTopic(t.id) } }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 960, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    // Level 1: subtopics of a category
    private func categoryView(_ c: Category) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack { BackButton(title: "Tất cả danh mục") { withAnimation(.smooth) { category = nil } }; Spacer() }
                HStack(spacing: 12) {
                    Image(systemName: c.symbol).font(.largeTitle).foregroundStyle(Color.parley.gradient)
                    Text(c.title).font(.largeTitle.weight(.bold))
                }
                if let error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], spacing: 14) {
                    ForEach(c.subtopics) { sub in
                        if let t = study.topic(for: sub) {
                            TopicCard(topic: Topic(id: t.id, title: sub.title, symbol: t.symbol, summary: t.summary, group: t.group, words: t.words),
                                      added: added(t)) { withAnimation(.smooth) { open = t } }
                        } else {
                            PendingTopicCard(title: sub.title, busy: generating == sub.id, available: ExampleWriter.available) {
                                Task { await generate(sub, in: c) }
                            }
                            .disabled(generating != nil)
                        }
                    }
                }
                Label("Chủ đề có biểu tượng ✨ được AI trên máy soạn khi bạn mở lần đầu (khoảng 10–30 giây), sau đó lưu lại. Chủ đề còn lại do Parley biên soạn sẵn.",
                      systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: 960, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func generate(_ sub: SubtopicRef, in c: Category) async {
        generating = sub.id
        error = nil
        defer { generating = nil }
        do {
            let t = try await study.generate(sub, in: c)
            withAnimation(.smooth) { open = t }
        } catch {
            self.error = "Không soạn được “\(sub.title)”: \(error.localizedDescription)"
        }
    }

    @ViewBuilder private var creator: some View {
        if ExampleWriter.available {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Tạo chủ đề mới bằng AI trên máy", systemImage: "sparkles").font(.headline).foregroundStyle(Color.parley)
                    HStack {
                        TextField("Ví dụ: phỏng vấn kỹ sư DevOps, đàm phán hợp đồng, bóng rổ…", text: $subject)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { Task { await create() } }
                        Button { Task { await create() } } label: {
                            if creating { ProgressView().controlSize(.small) } else { Label("Tạo", systemImage: "wand.and.stars") }
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(creating || subject.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Text("Tạo khoảng 12 từ kèm câu ví dụ, rồi dịch nghĩa offline. Mất khoảng 10–30 giây.").font(.caption).foregroundStyle(.secondary)
                }
            }
        } else {
            Text("Bật Apple Intelligence trong System Settings để AI soạn thêm chủ đề.").foregroundStyle(.secondary)
        }
    }

    private func create() async {
        let s = subject.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, !creating else { return }
        creating = true
        error = nil
        defer { creating = false }
        do {
            let topic = try await study.makeTopic(about: s, id: "custom-\(UUID().uuidString)", title: nil, symbol: "sparkles", group: "custom")
            withAnimation(.smooth) { study.addTopic(topic) }
            subject = ""
        } catch {
            self.error = "Không tạo được chủ đề: \(error.localizedDescription)"
        }
    }
}

struct CategoryCard: View {
    let category: Category
    let ready: Int
    let added: Int
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: category.symbol)
                    .font(.system(size: 30))
                    .foregroundStyle(.white)
                    .frame(width: 54, height: 54)
                    .background(Color.parley.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .symbolEffect(.bounce, value: hover)
                Text(category.title).font(.headline)
                Text("\(category.subtopics.count) chủ đề con · đã thêm \(added) từ").font(.callout).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                ProgressView(value: Double(ready), total: Double(max(category.subtopics.count, 1))).tint(.parley)
                Text("\(ready)/\(category.subtopics.count) chủ đề đã có từ").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
            .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(hover ? Color.parley.opacity(0.6) : Color.primary.opacity(0.08), lineWidth: hover ? 1.5 : 1))
            .shadow(color: .black.opacity(hover ? 0.12 : 0.04), radius: hover ? 12 : 6, y: hover ? 5 : 2)
            .scaleEffect(hover ? 1.015 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.snappy) { hover = h } }
    }
}

/// Subtopic whose words haven't been written yet (on-device AI writes them on first open).
struct PendingTopicCard: View {
    let title: String
    let busy: Bool
    let available: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "sparkles").font(.title).foregroundStyle(Color.parley.gradient)
                    .symbolEffect(.variableColor.iterative, isActive: busy)
                Text(title).font(.headline)
                Spacer(minLength: 0)
                if busy {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("AI đang soạn từ…").foregroundStyle(.secondary) }
                } else {
                    Text(available ? "Bấm để AI soạn ~12 từ" : "Cần bật Apple Intelligence").font(.callout).foregroundStyle(Color.parley)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
            .background(Color.parley.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.parley.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(!available || busy)
    }
}

struct TopicCard: View {
    let topic: Topic
    let added: Int
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: topic.symbol).font(.title).foregroundStyle(Color.parley.gradient).symbolEffect(.bounce, value: hover)
                Text(topic.title).font(.headline)
                Text(topic.summary).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                Spacer(minLength: 0)
                ProgressView(value: Double(added), total: Double(max(topic.words.count, 1))).tint(.parley)
                Text("Đã thêm \(added)/\(topic.words.count) từ").font(.caption).foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
            .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(hover ? Color.parley.opacity(0.6) : Color.primary.opacity(0.08), lineWidth: hover ? 1.5 : 1))
            .shadow(color: .black.opacity(hover ? 0.12 : 0.04), radius: hover ? 12 : 6, y: hover ? 5 : 2)
            .scaleEffect(hover ? 1.015 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.snappy) { hover = h } }
    }
}

struct TopicDetail: View {
    let topic: Topic
    let study: StudyStore
    let vocab: VocabStore
    let back: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    BackButton(title: "Tất cả chủ đề", action: back)
                    Spacer()
                    let missing = topic.words.filter { !vocab.contains($0.term) }
                    Button { missing.forEach(add) } label: { Label("Thêm cả chủ đề vào Học tập (\(missing.count))", systemImage: "plus.circle") }
                        .buttonStyle(.glassProminent)
                        .disabled(missing.isEmpty)
                }
                HStack(spacing: 12) {
                    Image(systemName: topic.symbol).font(.largeTitle).foregroundStyle(Color.parley.gradient)
                    VStack(alignment: .leading) {
                        Text(topic.title).font(.largeTitle.weight(.bold))
                        Text(topic.summary).foregroundStyle(.secondary)
                    }
                }
                ForEach(topic.words) { w in row(w) }
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func row(_ w: TopicWord) -> some View {
        let saved = vocab.contains(w.term)
        return Card(padding: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(w.term).font(.title3.weight(.bold))
                    if let ipa = Pronunciation.ipa(w.term) { Text(ipa).foregroundStyle(.secondary) }
                    Spacer()
                    SpeakButton { Speaker.speak(w.term, language: Locale.Language(identifier: "en-US")) }
                    if saved {
                        Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green).help("Đã có trong Học tập")
                    } else {
                        Button { add(w) } label: { Image(systemName: "plus").font(.title3).frame(width: 34, height: 34) }
                            .buttonStyle(.glassProminent)
                            .buttonBorderShape(.circle)
                            .help("Thêm vào Học tập")
                    }
                }
                Text(w.meaning).font(.body.weight(.medium))
                Text(highlightTerm(w.example, w.term)).font(.callout)
                Text(w.exampleTranslation).font(.callout).foregroundStyle(.secondary)
            }
        }
        .animation(.smooth, value: saved)
    }

    private func add(_ w: TopicWord) {
        vocab.add(VocabItem(term: w.term, meaning: w.meaning, termLanguage: "en-US", meaningLanguage: "vi",
                            ipa: Pronunciation.ipa(w.term), example: w.example, exampleTranslation: w.exampleTranslation, session: nil))
    }
}

// MARK: - Grammar

struct GrammarView: View {
    let study: StudyStore
    @State private var open: GrammarLesson?
    @State private var search = ""

    var body: some View {
        Group {
            if let open {
                LessonView(lesson: open, study: study) { withAnimation(.smooth) { self.open = nil } }
                    .id(open.id)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                list.transition(.opacity)
            }
        }
        .navigationTitle(open?.title ?? "Ngữ pháp")
        .problemBanner(study.problem)
        .task { if let id = DebugArgs.value("--open") { open = Library.grammar.first { $0.id == id } } }
    }

    private var list: some View {
        let numbered = Array(Library.grammar.enumerated())
        let filtered = numbered.filter { _, l in
            search.isEmpty || l.title.localizedCaseInsensitiveContains(search) || l.summary.localizedCaseInsensitiveContains(search)
        }
        let done = Library.grammar.count { study.data.grammarBest[$0.id] != nil }
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 16) {
                    Gauge(value: Double(done), in: 0...Double(max(Library.grammar.count, 1))) { EmptyView() } currentValueLabel: {
                        Text("\(done)").font(.caption.weight(.bold))
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(Color.parley)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Lộ trình ngữ pháp A1 → C1").font(.title3.weight(.semibold))
                        Text("\(Library.grammar.count) bài · \(Library.grammar.reduce(0) { $0 + $1.exercises.count }) câu bài tập · đã làm \(done) bài")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    TextField("Tìm bài (vd: bị động, used to…)", text: $search)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                }
                ForEach(Library.levels, id: \.code) { level in
                    let lessons = filtered.filter { $0.element.level == level.code }
                    if !lessons.isEmpty {
                        let levelDone = lessons.count { study.data.grammarBest[$0.element.id] != nil }
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(level.code)
                                    .font(.headline.weight(.heavy)).foregroundStyle(.white)
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(Color.parley.gradient, in: Capsule())
                                Text(level.title).font(.title3.weight(.semibold))
                                Text("\(levelDone)/\(lessons.count) bài").foregroundStyle(.secondary)
                                Spacer()
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                                ForEach(lessons, id: \.element.id) { i, lesson in
                                    LessonCard(number: i + 1, lesson: lesson, best: study.data.grammarBest[lesson.id]) {
                                        withAnimation(.smooth) { open = lesson }
                                    }
                                }
                            }
                        }
                    }
                }
                if filtered.isEmpty { ContentUnavailableView.search(text: search) }
            }
            .padding(24)
            .frame(maxWidth: 960, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

struct LessonCard: View {
    let number: Int
    let lesson: GrammarLesson
    let best: Int?
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Text("\(number)")
                    .font(.title2.weight(.heavy)).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.parley.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(lesson.title).font(.headline)
                    Text(lesson.summary).font(.callout).foregroundStyle(.secondary)
                    if let best {
                        Label("Điểm cao nhất \(best)/\(lesson.exercises.count)", systemImage: best == lesson.exercises.count ? "star.fill" : "star.leadinghalf.filled")
                            .font(.caption.weight(.semibold)).foregroundStyle(best == lesson.exercises.count ? .orange : .secondary)
                    } else {
                        Text("Chưa làm bài").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(hover ? Color.parley.opacity(0.6) : Color.primary.opacity(0.08), lineWidth: hover ? 1.5 : 1))
            .scaleEffect(hover ? 1.01 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.snappy) { hover = h } }
    }
}

struct LessonView: View {
    let lesson: GrammarLesson
    let study: StudyStore
    let back: () -> Void
    @State private var quiz = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    BackButton(title: "Tất cả bài", action: back)
                    Spacer()
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if let level = lesson.level {
                        Text(level).font(.headline.weight(.heavy)).foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Color.parley.gradient, in: Capsule())
                    }
                    Text(lesson.title).font(.largeTitle.weight(.bold))
                }
                Text(lesson.summary).font(.title3).foregroundStyle(.secondary)
                if quiz {
                    GrammarQuiz(lesson: lesson, onAnswer: { study.answerGrammar(correct: $0) }) { score in study.recordGrammar(lesson.id, score: score) } onClose: { withAnimation { quiz = false } }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    section("Khi nào dùng", "lightbulb.fill") { Text(lesson.when) }
                    section("Công thức", "function") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(lesson.form, id: \.self) { Text($0).font(.body.monospaced()) }
                        }
                    }
                    section("Ví dụ", "quote.bubble.fill") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(lesson.examples, id: \.en) { ex in
                                HStack(alignment: .top, spacing: 10) {
                                    SpeakButton { Speaker.speak(ex.en, language: Locale.Language(identifier: "en-US")) }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(ex.en).font(.body.weight(.medium))
                                        Text(ex.vi).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    section("Lỗi hay gặp", "exclamationmark.triangle.fill", tint: .orange) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(lesson.tips, id: \.self) { Label($0, systemImage: "xmark.circle").labelStyle(.titleAndIcon) }
                        }
                    }
                    Button { withAnimation(.smooth) { quiz = true } } label: {
                        Label("Làm bài tập (\(lesson.exercises.count) câu)", systemImage: "pencil.and.list.clipboard")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                }
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func section<C: View>(_ title: String, _ symbol: String, tint: Color = .parley, @ViewBuilder content: () -> C) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: symbol).font(.headline).foregroundStyle(tint)
                content()
            }
        }
    }
}

struct GrammarQuiz: View {
    let lesson: GrammarLesson
    var onAnswer: (Bool) -> Void = { _ in }
    let onFinish: (Int) -> Void
    let onClose: () -> Void
    @State private var index = 0
    @State private var chosen: String?
    @State private var score = 0
    @State private var shakes = 0

    var body: some View {
        Card(padding: 24) {
            if index < lesson.exercises.count {
                let ex = lesson.exercises[index]
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Câu \(index + 1)/\(lesson.exercises.count)").font(.headline).foregroundStyle(.secondary)
                        Spacer()
                        Label("\(score)", systemImage: "star.fill").foregroundStyle(.orange).contentTransition(.numericText())
                    }
                    ProgressView(value: Double(index), total: Double(lesson.exercises.count)).tint(.parley)
                    Text(ex.prompt).font(.title2.weight(.semibold))
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                        ForEach(Array(ex.options.enumerated()), id: \.offset) { i, opt in
                            let tint: Color = chosen == nil ? .parley : opt == ex.answer ? .green : opt == chosen ? .red : .secondary
                            Button { choose(opt, ex) } label: {
                                HStack {
                                    Text("\(i + 1)").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                                    Text(opt).font(.body.weight(.medium))
                                    Spacer()
                                    if chosen != nil, opt == ex.answer { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                                .background(tint.opacity(chosen == nil ? 0.06 : 0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tint.opacity(0.35)))
                                .contentShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .disabled(chosen != nil)
                            .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [])
                        }
                    }
                    if let chosen {
                        let ok = chosen == ex.answer
                        VStack(alignment: .leading, spacing: 6) {
                            Label(ok ? "Chính xác!" : "Chưa đúng — đáp án: \(ex.answer)", systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.headline).foregroundStyle(ok ? .green : .red)
                            Text(ex.explain)
                            Text(ex.prompt.replacingOccurrences(of: "___", with: ex.answer)).foregroundStyle(.secondary).italic()
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        HStack {
                            Spacer()
                            Button { next() } label: { Label(index + 1 < lesson.exercises.count ? "Câu tiếp" : "Xem kết quả", systemImage: "arrow.right") }
                                .buttonStyle(.glassProminent)
                                .keyboardShortcut(.defaultAction)
                        }
                    }
                }
                .modifier(Shake(shakes: CGFloat(shakes)))
                .animation(.spring(duration: 0.35), value: chosen)
            } else {
                VStack(spacing: 14) {
                    Image(systemName: score == lesson.exercises.count ? "trophy.fill" : "checkmark.seal.fill")
                        .font(.system(size: 56)).foregroundStyle(Color.parley.gradient).symbolEffect(.bounce, options: .repeat(2))
                    Text("\(score)/\(lesson.exercises.count) câu đúng").font(.title.weight(.bold))
                    Text(score == lesson.exercises.count ? "Hoàn hảo! Bạn đã nắm chắc bài này." : "Đọc lại phần ví dụ và lỗi hay gặp rồi thử lại nhé.")
                        .foregroundStyle(.secondary)
                    HStack {
                        Button { index = 0; score = 0; chosen = nil } label: { Label("Làm lại", systemImage: "arrow.clockwise") }
                            .buttonStyle(.glass)
                        Button(action: onClose) { Label("Xem lại bài học", systemImage: "book") }
                            .buttonStyle(.glassProminent)
                    }
                }
                .frame(maxWidth: .infinity)
                .onAppear { onFinish(score) }
            }
        }
    }

    private func choose(_ option: String, _ ex: GrammarExercise) {
        guard chosen == nil else { return }
        chosen = option
        onAnswer(option == ex.answer)
        if option == ex.answer { withAnimation { score += 1 } } else { withAnimation(.linear(duration: 0.4)) { shakes += 1 } }
    }

    private func next() {
        chosen = nil
        index += 1
    }
}
