import Foundation
import FoundationModels
import SwiftUI

// MARK: - Passages

struct ReadingQuestion: Codable, Hashable {
    var prompt: String
    var options: [String]
    var answer: String
    var explainVi: String
}

struct Passage: Codable, Identifiable, Hashable {
    var id: String
    var level: String     // A2…C1
    var title: String
    var topic: String     // Vietnamese
    var text: String
    var questions: [ReadingQuestion]
    var generated: Bool?  // written by the on-device model
}

/// Pure, tested rules for reading passages (bundled or generated).
enum ReadingRules {
    static let minWords = 80
    static let maxWords = 400

    static func paragraphs(_ text: String) -> [String] {
        text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Keeps questions that can be marked: a prompt, exactly 4 distinct options, the answer among them.
    static func validQuestions(_ qs: [ReadingQuestion]) -> [ReadingQuestion] {
        qs.compactMap { q in
            let options = q.options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let answer = q.answer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !q.prompt.trimmingCharacters(in: .whitespaces).isEmpty, options.count == 4,
                  Set(options.map { $0.lowercased() }).count == 4, options.allSatisfy({ !$0.isEmpty }),
                  let match = options.first(where: { $0.caseInsensitiveCompare(answer) == .orderedSame }) else { return nil }
            return ReadingQuestion(prompt: q.prompt, options: options, answer: match, explainVi: q.explainVi)
        }
    }

    static let questionCount = 3

    /// Vietnamese reason a passage can't be used; nil when it is fine (AC6.3: exactly 3 valid questions).
    static func problem(with p: Passage) -> String? {
        let words = WritingRules.wordCount(p.text)
        if p.title.trimmingCharacters(in: .whitespaces).isEmpty { return "Bài đọc thiếu tiêu đề." }
        if words < minWords || words > maxWords { return "Bài đọc dài \(words) từ (cần \(minWords)–\(maxWords))." }
        if validQuestions(p.questions).count != questionCount { return "Bài đọc cần đúng \(questionCount) câu hỏi hợp lệ." }
        return nil
    }

    /// Target length per level for generated passages (A2 texts came back too short without it).
    static func wordTarget(_ level: CEFR) -> ClosedRange<Int> {
        switch level {
        case .a2: 100...150
        case .b1: 140...200
        case .b2, .c1: 180...250
        }
    }

    /// A generated answer must come from the text: at least half of its content words (or the whole short answer)
    /// appear in it. The small on-device model sometimes asks about things the text never says.
    static func supported(_ answer: String, by text: String) -> Bool {
        let t = " " + text.lowercased() + " "
        let stop: Set<String> = ["the", "and", "that", "this", "with", "from", "they", "their", "there", "about", "into", "have", "were", "will"]
        let words = answer.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count > 3 && !stop.contains($0) }
        guard !words.isEmpty else { return t.contains(answer.lowercased()) }
        let found = words.count { w in t.contains(w) || t.contains(String(w.prefix(5))) }
        return Double(found) / Double(words.count) >= 0.5
    }

    /// An explanation only counts when it is Vietnamese (the model sometimes answers in English).
    static func vietnameseOrEmpty(_ s: String) -> String { WritingRules.isVietnamese(s) ? s : "" }

    /// The options in a stable order that doesn't depend on how they were written (the right answer is often the
    /// longest or listed first): sorted by a deterministic FNV-1a hash of passage id + option.
    static func displayOrder(_ q: ReadingQuestion, seed: String) -> [String] {
        func fnv(_ s: String) -> UInt64 { s.utf8.reduce(14695981039346656037) { ($0 ^ UInt64($1)) &* 1099511628211 } }
        return q.options.sorted { (fnv(seed + $0), $0) < (fnv(seed + $1), $1) }
    }

    static func score(_ answers: [Int: String], _ questions: [ReadingQuestion]) -> Int {
        questions.indices.count { answers[$0] == questions[$0].answer }
    }
}

@Generable struct GeneratedPassage {
    @Guide(description: "A short English title")
    var title: String
    @Guide(description: "An English text in 3 or 4 paragraphs separated by a blank line, at the length and CEFR level the request asks for")
    var text: String
    @Guide(description: "Exactly 3 comprehension questions about the text")
    var questions: [GeneratedQuestion]
}

@Generable struct GeneratedQuestion {
    @Guide(description: "A question in English")
    var prompt: String
    @Guide(description: "Exactly 4 different short answer options in English")
    var options: [String]
    @Guide(description: "The correct option, copied exactly from the options")
    var answer: String
    @Guide(description: "One sentence in Vietnamese explaining where the answer is in the text")
    var explainVi: String
}

/// One visit to a passage's quiz: answers, and which questions already earned XP (a retry earns nothing).
struct ReadingQuiz: Equatable {
    let questions: [ReadingQuestion]
    private(set) var answers: [Int: String] = [:]
    private(set) var scored: Set<Int> = []

    init(_ questions: [ReadingQuestion]) { self.questions = questions }

    /// Records an answer; returns the XP event the first time question `i` is answered in this visit.
    mutating func choose(_ i: Int, _ option: String) -> XPEvent? {
        guard questions.indices.contains(i), answers[i] == nil else { return nil }
        answers[i] = option
        guard scored.insert(i).inserted else { return nil }
        return .reading(ok: option == questions[i].answer)
    }

    mutating func retry() { answers = [:] }
    var finished: Bool { answers.count == questions.count && !questions.isEmpty }
    var score: Int { ReadingRules.score(answers, questions) }
}

/// What a passage writer returns before the rules run.
struct DraftPassage {
    var title: String
    var text: String
    var questions: [ReadingQuestion]
}

@MainActor protocol PassageWriter {
    func write(topic: String, level: CEFR) async throws -> DraftPassage
}

/// The on-device model as a passage writer (60 s limit).
struct ModelPassageWriter: PassageWriter {
    nonisolated static let timeout = 60.0

    func write(topic: String, level: CEFR) async throws -> DraftPassage {
        let target = ReadingRules.wordTarget(level)
        let ask = "Write a reading passage for a Vietnamese adult learner at CEFR \(level.rawValue) (\(level.hint)) about: \(topic). "
            + "Use \(target.lowerBound) to \(target.upperBound) words in 3 or 4 paragraphs and American spelling. "
            + "Write exactly 3 questions whose answers are stated in the text; only one option may be correct; explanations in Vietnamese."
        let g = try await modelTimeout(Self.timeout) {
            try await LanguageModelSession(instructions: "You write clear, accurate graded reading texts and fair comprehension questions.")
                .respond(to: ask, generating: GeneratedPassage.self).content
        }
        return DraftPassage(title: g.title, text: g.text, questions: g.questions.map {
            ReadingQuestion(prompt: $0.prompt, options: $0.options, answer: $0.answer, explainVi: $0.explainVi)
        })
    }
}

// MARK: - Store (generated passages and best scores)

struct ReadingData: Codable, Equatable {
    var generated: [Passage] = []
    var best: [String: Int] = [:]
    var xpDay: [String: String]? = [:]  // passage id → the day it last earned XP (once per passage per day)
}

@Observable @MainActor
final class ReadingStore {
    private(set) var data = ReadingData()
    private(set) var problem: String?
    @ObservationIgnored private let url: URL
    @ObservationIgnored private var writable = true
    @ObservationIgnored private let activity: ActivityStore?

    init(file: URL = Model.dataDir.appending(path: "reading.json"), activity: ActivityStore? = nil) {
        url = file
        self.activity = activity
        let loaded = StoreFile.load(ReadingData.self, from: url)
        data = loaded.value ?? ReadingData()
        writable = loaded.writable
        problem = loaded.problem
    }

    /// Bundled passages first (by level), then the ones written on this Mac (newest first).
    var all: [Passage] { Library.readings + data.generated }

    /// Off for v0.2.0: the on-device model could not reliably write passages with correct quizzes (PARLEY-6 review,
    /// 0 of 4 real runs). The writer and its rules stay tested; the UI comes back with backlog item PARLEY-19.
    nonisolated static let generatorEnabled = false

    /// Reading XP from `ReadingQuiz.choose` (10 right / 2 wrong; nil = already earned in this visit), and at most once
    /// per passage per day — leaving and reopening a passage earns nothing more.
    func log(_ event: XPEvent?, passage id: String, now: Date = .now) {
        guard let event, visits[id] != .doneToday else { return }
        visits[id] = .earningThisVisit // the visit's remaining questions still count
        activity?.log(event, now: now)
        var seen = data.xpDay ?? [:]
        seen[id] = StudyStore.day(now)
        data.xpDay = seen
        save()
    }

    enum Visit { case earningThisVisit, doneToday }
    @ObservationIgnored private var visits: [String: Visit] = [:]

    /// Called when a passage opens: if it already earned XP today (this run or an earlier one), this visit earns none.
    func beginVisit(_ id: String, now: Date = .now) {
        let earnedToday = data.xpDay?[id] == StudyStore.day(now)
        visits[id] = earnedToday ? .doneToday : nil
    }

    func earnedToday(_ id: String, now: Date = .now) -> Bool { data.xpDay?[id] == StudyStore.day(now) }

    /// Whether the reading list shows the AI generator card (off for v0.2.0).
    nonisolated static func showsGenerator(enabled: Bool = generatorEnabled) -> Bool { enabled }

    func finish(_ id: String, score: Int) {
        data.best[id] = max(data.best[id] ?? 0, score)
        save()
    }

    func add(_ p: Passage) {
        data.generated.insert(p, at: 0)
        save()
    }

    func remove(_ id: String) {
        data.generated.removeAll { $0.id == id }
        data.best[id] = nil
        save()
    }

    /// Writes a new passage (one retry when the result is unusable — not after a timeout, which already waited long).
    static func generate(topic: String, level: CEFR, now: Date = .now, writer: PassageWriter? = nil) async throws -> Passage {
        let writer = writer ?? ModelPassageWriter()
        do { return try build(try await writer.write(topic: topic, level: level), topic: topic, level: level, now: now) }
        catch let e as TimeoutError { throw e }
        catch is CancellationError { throw CancellationError() }
        catch {
            print("reading: first attempt unusable:", error)
            return try build(try await writer.write(topic: topic, level: level), topic: topic, level: level, now: now)
        }
    }

    /// The model's draft through the same rules as bundled passages, plus "answers come from the text".
    static func build(_ d: DraftPassage, topic: String, level: CEFR, now: Date) throws -> Passage {
        let text = d.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let questions = ReadingRules.validQuestions(d.questions.map {
            ReadingQuestion(prompt: $0.prompt, options: $0.options, answer: $0.answer, explainVi: ReadingRules.vietnameseOrEmpty($0.explainVi))
        }).filter { ReadingRules.supported($0.answer, by: text) }
        let p = Passage(id: "gen-\(Int(now.timeIntervalSince1970))", level: level.rawValue, title: d.title, topic: topic,
                        text: text, questions: questions, generated: true)
        if let problem = ReadingRules.problem(with: p) { throw Err("AI tạo bài chưa đạt: \(problem) Thử lại nhé.") }
        return p
    }

    private func save() {
        guard writable else { return }
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        do { try StoreFile.save(data, to: url, encoder: e) } catch { problem = "Không lưu được bài đọc: \(error.localizedDescription)" }
    }
}

// MARK: - "Đọc hiểu" screen

struct ReadingView: View {
    let store: ReadingStore
    let vocab: VocabStore
    @State private var level: String?
    @State private var open: Passage?
    @State private var topic = ""
    @State private var genLevel = CEFR.b1
    @State private var generating = false
    @State private var error: String?
    @State private var job: Task<Void, Never>? // cancelled when the learner leaves the screen

    var body: some View {
        Group {
            if let open {
                PassageView(passage: open, store: store, vocab: vocab) { withAnimation(.smooth) { self.open = nil } }
                    .id(open.id)
            } else {
                list
            }
        }
        .navigationTitle(open?.title ?? "Đọc hiểu")
        .onDisappear { job?.cancel() }
        .problemBanner(store.problem)
        .task {
            if let id = DebugArgs.value("--open"), let p = store.all.first(where: { $0.id == id }) { open = p }
        }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Bôi đen một từ trong bài để xem nghĩa, phát âm và lưu vào từ vựng. Trả lời câu hỏi để kiểm tra mức hiểu.",
                              systemImage: "text.magnifyingglass")
                            .foregroundStyle(.secondary)
                        Picker("Trình độ", selection: $level) {
                            Text("Tất cả").tag(String?.none)
                            ForEach(CEFR.allCases) { Text($0.rawValue).tag(Optional($0.rawValue)) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: 320)
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                    ForEach(store.all.filter { level == nil || $0.level == level }) { p in
                        Button { withAnimation(.smooth) { open = p } } label: { PassageCard(passage: p, best: store.data.best[p.id]) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if p.generated == true { Button("Xoá bài này", systemImage: "trash", role: .destructive) { store.remove(p.id) } }
                            }
                    }
                }
                if ReadingStore.showsGenerator() { generator }
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var generator: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Label("Tạo bài đọc mới bằng AI trên máy", systemImage: "sparkles").font(.headline)
                if ExampleWriter.available {
                    HStack {
                        TextField("Chủ đề, ví dụ: cloud computing, đi du lịch Nhật Bản…", text: $topic)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { startGenerate() }
                        Picker("Trình độ", selection: $genLevel) { ForEach(CEFR.allCases) { Text($0.rawValue).tag($0) } }
                            .labelsHidden().frame(width: 80)
                        Button { startGenerate() } label: { Label(generating ? "Đang viết…" : "Tạo bài", systemImage: "wand.and.stars") }
                            .buttonStyle(.glassProminent)
                            .disabled(generating || topic.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if generating { ProgressView().controlSize(.small) }
                } else {
                    Text("Cần bật Apple Intelligence (System Settings → Apple Intelligence & Siri). Các bài có sẵn vẫn đọc được.")
                        .foregroundStyle(.secondary)
                }
                if let error { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
            }
        }
    }

    private func startGenerate() {
        job?.cancel()
        job = Task { await generate() }
    }

    private func generate() async {
        let t = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !generating else { return }
        generating = true
        error = nil
        defer { generating = false }
        do {
            let p = try await ReadingStore.generate(topic: t, level: genLevel)
            store.add(p)
            topic = ""
            withAnimation(.smooth) { open = p }
        } catch is CancellationError {
            return
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? "AI chưa viết được bài — thử lại hoặc đổi chủ đề."
        }
    }
}

struct PassageCard: View {
    let passage: Passage
    let best: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(passage.level).font(.caption.weight(.bold)).foregroundStyle(Color.parley)
                    .padding(.horizontal, 8).padding(.vertical, 3).background(Color.parley.opacity(0.12), in: Capsule())
                if passage.generated == true { Image(systemName: "sparkles").foregroundStyle(.secondary).help("Do AI trên máy viết") }
                Spacer()
                if let best { Text("\(best)/\(passage.questions.count)").font(.callout.weight(.semibold)).foregroundStyle(.green) }
            }
            Text(passage.title).font(.headline).fixedSize(horizontal: false, vertical: true)
            Text("\(passage.topic) · \(WritingRules.wordCount(passage.text)) từ").font(.callout).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

struct PassageView: View {
    let passage: Passage
    let store: ReadingStore
    let vocab: VocabStore
    let onBack: () -> Void
    @State private var quiz: ReadingQuiz
    @State private var reading = false

    init(passage: Passage, store: ReadingStore, vocab: VocabStore, onBack: @escaping () -> Void) {
        self.passage = passage
        self.store = store
        self.vocab = vocab
        self.onBack = onBack
        _quiz = State(initialValue: ReadingQuiz(ReadingRules.validQuestions(passage.questions)))
    }

    private var questions: [ReadingQuestion] { quiz.questions }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                BackButton(title: "Bài đọc", action: { Speaker.stop(); onBack() })
                Text(passage.level).font(.headline).foregroundStyle(Color.parley)
                Text(passage.topic).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button {
                    if reading { Speaker.stop() } else { Speaker.speak(passage.text, language: Locale.Language(identifier: "en-US")) }
                    reading.toggle()
                } label: { Label(reading ? "Dừng đọc" : "Nghe cả bài", systemImage: reading ? "stop.fill" : "speaker.wave.2.fill") }
                    .buttonStyle(.glass)
            }
            .padding([.horizontal, .top], 20)
            HStack(alignment: .top, spacing: 16) {
                TranscriptView(lines: ReadingRules.paragraphs(passage.text).map { .init(time: "", source: .system, text: $0, counterpart: "") },
                               language: Locale.Language(identifier: "en-US"), other: Locale.Language(identifier: "vi"),
                               session: nil, vocab: vocab, showMeta: false)
                    .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
                    .frame(minWidth: 320)
                ScrollView { quizPanel }
                    .frame(minWidth: 260, idealWidth: 340, maxWidth: 380)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .onDisappear { Speaker.stop() }
        .onAppear { store.beginVisit(passage.id) }
        .task(id: reading) { // the button returns to "Nghe cả bài" when the speech ends by itself
            while reading, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                if !Speaker.isSpeaking { reading = false }
            }
        }
    }

    private var quizPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Câu hỏi").font(.headline)
            if store.earnedToday(passage.id), quiz.answers.isEmpty {
                Label("Hôm nay bài này đã được tính XP — làm lại để ôn, không cộng thêm.", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(questions.enumerated()), id: \.offset) { i, q in
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(i + 1). \(q.prompt)").font(.callout.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    ForEach(ReadingRules.displayOrder(q, seed: passage.id), id: \.self) { o in
                        let picked = quiz.answers[i]
                        let tint: Color = picked == nil ? .parley : o == q.answer ? .green : o == picked ? .red : .secondary
                        Button { choose(i, o) } label: {
                            HStack {
                                Text(o).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                if picked != nil, o == q.answer { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(tint.opacity(picked == nil ? 0.06 : 0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .disabled(picked != nil)
                        .accessibilityLabel(picked == nil ? o : o == q.answer ? "\(o), đáp án đúng" : o == picked ? "\(o), bạn chọn, chưa đúng" : o)
                    }
                    if quiz.answers[i] != nil, !q.explainVi.isEmpty { Text(q.explainVi).font(.caption).foregroundStyle(.secondary) }
                }
                .padding(12)
                .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            }
            if quiz.finished {
                let s = quiz.score
                Label("Đúng \(s)/\(questions.count) câu", systemImage: s == questions.count ? "trophy.fill" : "checkmark.seal.fill")
                    .font(.headline).foregroundStyle(Color.parley)
                Button("Làm lại (không tính thêm XP)") { quiz.retry() }.buttonStyle(.glass)
            }
        }
    }

    private func choose(_ i: Int, _ option: String) {
        store.log(quiz.choose(i, option), passage: passage.id)
        if quiz.finished { store.finish(passage.id, score: quiz.score) }
    }
}
