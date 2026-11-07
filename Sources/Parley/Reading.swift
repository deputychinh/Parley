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

    /// Vietnamese reason a passage can't be used; nil when it is fine.
    static func problem(with p: Passage) -> String? {
        let words = WritingRules.wordCount(p.text)
        if p.title.trimmingCharacters(in: .whitespaces).isEmpty { return "Bài đọc thiếu tiêu đề." }
        if words < minWords || words > maxWords { return "Bài đọc dài \(words) từ (cần \(minWords)–\(maxWords))." }
        if validQuestions(p.questions).count < 2 { return "Bài đọc cần ít nhất 2 câu hỏi hợp lệ." }
        return nil
    }

    static func score(_ answers: [Int: String], _ questions: [ReadingQuestion]) -> Int {
        questions.indices.count { answers[$0] == questions[$0].answer }
    }
}

@Generable struct GeneratedPassage {
    @Guide(description: "A short English title")
    var title: String
    @Guide(description: "An English text of 150 to 220 words in 3 or 4 paragraphs separated by a blank line, written for the requested CEFR level")
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

// MARK: - Store (generated passages and best scores)

struct ReadingData: Codable, Equatable {
    var generated: [Passage] = []
    var best: [String: Int] = [:]
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

    /// One answered question: reading XP (10 right / 2 wrong).
    func answer(correct: Bool) { activity?.log(.reading(ok: correct)) }

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

    /// Writes a new passage with the on-device model; throws a Vietnamese error when the result is unusable.
    static func generate(topic: String, level: CEFR, now: Date = .now) async throws -> Passage {
        let ask = "Write a reading passage for a Vietnamese adult learner at CEFR \(level.rawValue) (\(level.hint)) about: \(topic)."
        let g = try await withTimeout(60) {
            try await LanguageModelSession(instructions: "You write clear, accurate graded reading texts and fair comprehension questions.")
                .respond(to: ask, generating: GeneratedPassage.self).content
        }
        let questions = ReadingRules.validQuestions(g.questions.map {
            ReadingQuestion(prompt: $0.prompt, options: $0.options, answer: $0.answer, explainVi: $0.explainVi)
        })
        let p = Passage(id: "gen-\(Int(now.timeIntervalSince1970))", level: level.rawValue, title: g.title, topic: topic,
                        text: g.text.trimmingCharacters(in: .whitespacesAndNewlines), questions: questions, generated: true)
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
                generator
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
                            .onSubmit { Task { await generate() } }
                        Picker("Trình độ", selection: $genLevel) { ForEach(CEFR.allCases) { Text($0.rawValue).tag($0) } }
                            .labelsHidden().frame(width: 80)
                        Button { Task { await generate() } } label: { Label(generating ? "Đang viết…" : "Tạo bài", systemImage: "wand.and.stars") }
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
        } catch {
            self.error = (error as? Err)?.localizedDescription ?? "AI chưa viết được bài — thử lại hoặc đổi chủ đề."
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
    @State private var answers: [Int: String] = [:]
    @State private var reading = false

    private var questions: [ReadingQuestion] { ReadingRules.validQuestions(passage.questions) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                BackButton(title: "Bài đọc", action: { Speaker.stop(); onBack() })
                Text(passage.level).font(.headline).foregroundStyle(Color.parley)
                Text(passage.title).font(.title3.weight(.semibold)).lineLimit(1)
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
                ScrollView { quiz }
                    .frame(minWidth: 260, idealWidth: 340, maxWidth: 380)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .onDisappear { Speaker.stop() }
    }

    private var quiz: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Câu hỏi").font(.headline)
            ForEach(Array(questions.enumerated()), id: \.offset) { i, q in
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(i + 1). \(q.prompt)").font(.callout.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    ForEach(q.options, id: \.self) { o in
                        let picked = answers[i]
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
                        .accessibilityLabel(picked == nil ? o : (o == q.answer ? "\(o), đáp án đúng" : o))
                    }
                    if answers[i] != nil, !q.explainVi.isEmpty { Text(q.explainVi).font(.caption).foregroundStyle(.secondary) }
                }
                .padding(12)
                .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            }
            if answers.count == questions.count, !questions.isEmpty {
                let s = ReadingRules.score(answers, questions)
                Label("Đúng \(s)/\(questions.count) câu", systemImage: s == questions.count ? "trophy.fill" : "checkmark.seal.fill")
                    .font(.headline).foregroundStyle(Color.parley)
                Button("Làm lại") { answers = [:] }.buttonStyle(.glass)
            }
        }
    }

    private func choose(_ i: Int, _ option: String) {
        guard answers[i] == nil else { return }
        answers[i] = option
        store.answer(correct: option == questions[i].answer)
        if answers.count == questions.count { store.finish(passage.id, score: ReadingRules.score(answers, questions)) }
    }
}
