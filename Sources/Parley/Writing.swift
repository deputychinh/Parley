import Foundation
import FoundationModels
import SwiftUI

// MARK: - Prompts

struct WritingPrompt: Identifiable, Hashable {
    let id: String
    let level: CEFR
    let title: String   // Vietnamese
    let task: String    // English instruction shown to the learner

    static let all: [WritingPrompt] = [
        WritingPrompt(id: "a2-weekend", level: .a2, title: "Cuối tuần của bạn", task: "Write about what you did last weekend."),
        WritingPrompt(id: "a2-team", level: .a2, title: "Giới thiệu nhóm", task: "Introduce your team at work: who they are and what they do."),
        WritingPrompt(id: "a2-routine", level: .a2, title: "Một ngày làm việc", task: "Describe a normal working day from morning to evening."),
        WritingPrompt(id: "b1-sick", level: .b1, title: "Xin nghỉ ốm", task: "Write an email to your manager: you are sick today and explain how your work will be covered."),
        WritingPrompt(id: "b1-standup", level: .b1, title: "Cập nhật tiến độ", task: "Write a short status update: what you finished, what you are doing next, and one blocker."),
        WritingPrompt(id: "b1-trip", level: .b1, title: "Chuyến đi đáng nhớ", task: "Tell the story of a trip you remember well and why."),
        WritingPrompt(id: "b2-delay", level: .b2, title: "Báo trễ deadline", task: "Write to a client: the release will be one week late. Explain why and what you will do."),
        WritingPrompt(id: "b2-review", level: .b2, title: "Góp ý code review", task: "Write polite review comments asking a colleague to change their approach."),
        WritingPrompt(id: "b2-remote", level: .b2, title: "Làm việc từ xa", task: "Give your opinion: is remote work better than working in the office?"),
        WritingPrompt(id: "c1-proposal", level: .c1, title: "Đề xuất kỹ thuật", task: "Propose a technical change to your team and argue for it, including the risks."),
        WritingPrompt(id: "c1-postmortem", level: .c1, title: "Báo cáo sự cố", task: "Write a short incident postmortem: impact, root cause and actions."),
        WritingPrompt(id: "c1-ai", level: .c1, title: "AI trong công việc", task: "Discuss how AI tools will change your job in the next five years."),
    ]
}

// MARK: - Model output and stored feedback

@Generable struct GeneratedCritique {
    @Guide(description: "The learner's whole text with only grammar, spelling and word-choice mistakes fixed; never add or remove sentences, even if the text does not match the task")
    var corrected: String
    @Guide(description: "Up to 8 of the most important mistakes, in the order they appear")
    var mistakes: [GeneratedMistake]
    @Guide(description: "Estimated CEFR level of the writing: one of A1, A2, B1, B2, C1, C2")
    var level: String
    @Guide(description: "Two short sentences in Vietnamese: what was good and what to work on next")
    var summaryVi: String
}

@Generable struct GeneratedMistake {
    @Guide(description: "The exact words copied from the learner's text that contain the mistake")
    var original: String
    @Guide(description: "The corrected words in English (never Vietnamese)")
    var fix: String
    @Guide(description: "One sentence in Vietnamese naming the rule, e.g. 'Dùng quá khứ đơn vì việc đã xảy ra hôm qua.'")
    var explanationVi: String
}

struct Mistake: Codable, Hashable {
    var original: String
    var fix: String
    var explanation: String
}

struct WritingEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var date = Date()
    var prompt: String
    var text: String
    var corrected: String
    var mistakes: [Mistake]
    var level: String
    var summary: String
}

/// Pure, tested rules of the writing coach.
enum WritingRules {
    static let minWords = 20
    static let maxWords = 250
    static let levels = ["A1", "A2", "B1", "B2", "C1", "C2"]

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count { !Answer.normalize(String($0)).isEmpty }
    }

    /// Vietnamese message when the text can't be sent yet; nil when it is ready.
    static func problem(with text: String) -> String? {
        let n = wordCount(text)
        if n < minWords { return "Viết thêm ít nhất \(minWords - n) từ nữa (tối thiểu \(minWords) từ)." }
        if n > maxWords { return "Bài dài \(n) từ — AI trên máy chỉ chấm tối đa \(maxWords) từ, hãy rút gọn." }
        return nil
    }

    /// Drops model mistakes that aren't real: no change, or "original" words that aren't in the learner's text.
    static func clean(_ mistakes: [(original: String, fix: String, explanation: String)], in text: String) -> [Mistake] {
        var seen = Set<String>()
        return mistakes.compactMap { m in
            let o = m.original.trimmingCharacters(in: .whitespacesAndNewlines)
            let f = m.fix.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !o.isEmpty, !f.isEmpty, !isVietnamese(f), WordDiff.key(o) != WordDiff.key(f),
                  text.range(of: o, options: [.caseInsensitive, .diacriticInsensitive]) != nil,
                  seen.insert(o.lowercased()).inserted else { return nil }
            return Mistake(original: o, fix: f, explanation: m.explanation.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// The small model sometimes "fixes" a phrase by translating it; a correction must stay English.
    static func isVietnamese(_ s: String) -> Bool {
        s.range(of: "[ăâđêôơưàáảãạằắẳẵặầấẩẫậèéẻẽẹềếểễệìíỉĩịòóỏõọồốổỗộờớởỡợùúủũụừứửữựỳýỷỹỵ]",
                options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// The model's rewrite is trusted only while it stays a correction: it keeps ≥ 70 % of the learner's words and
    /// grows by ≤ 30 %; otherwise the learner's text is the base. The listed mistakes are always applied on top, so
    /// the corrected text and the mistake list never disagree.
    static func correctedText(original: String, model: String, mistakes: [Mistake]) -> String {
        let m = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let kept = WordDiff.score(WordDiff.diff(expected: original, typed: m))      // share of original words still there
        let growth = Double(wordCount(m)) / Double(max(wordCount(original), 1))
        let base = !m.isEmpty && kept >= 0.7 && growth <= 1.3 ? m : original
        return apply(mistakes, to: base)
    }

    /// Replaces each mistake's first whole-word occurrence (case-insensitive), in order — "I learn" never matches
    /// inside "I learned", so applying a fix twice is a no-op.
    static func apply(_ mistakes: [Mistake], to text: String) -> String {
        var out = text
        for m in mistakes {
            let pattern = "(?<![\\p{L}\\p{N}'])" + NSRegularExpression.escapedPattern(for: m.original) + "(?![\\p{L}\\p{N}'])"
            if let r = out.range(of: pattern, options: [.regularExpression, .caseInsensitive]) { out.replaceSubrange(r, with: m.fix) }
        }
        return out
    }

    /// "b1", "B1+", "around B2" → "B2"; unknown → "?".
    static func level(_ raw: String) -> String {
        let up = raw.uppercased()
        return levels.reversed().first { up.contains($0) } ?? "?"
    }

    static let instructions = """
        You are a kind, precise English writing teacher for Vietnamese adult learners. Correct only real mistakes \
        (grammar, spelling, word choice, articles, prepositions, tense); keep the learner's ideas and voice and never \
        add new sentences. \
        Explanations are in Vietnamese and name the grammar rule.
        """
}

@Observable @MainActor
final class WritingStore {
    private(set) var entries: [WritingEntry] = []
    private(set) var problem: String?
    @ObservationIgnored private let url: URL
    @ObservationIgnored private var writable = true
    @ObservationIgnored private let activity: ActivityStore?

    init(file: URL = Model.dataDir.appending(path: "writing.json"), activity: ActivityStore? = nil) {
        url = file
        self.activity = activity
        let loaded = StoreFile.load([WritingEntry].self, from: url, decoder: Self.decoder)
        entries = loaded.value ?? []
        writable = loaded.writable
        problem = loaded.problem
    }

    /// Saves a reviewed text (newest first) and logs writing XP.
    func add(_ entry: WritingEntry) {
        entries.insert(entry, at: 0)
        save()
        activity?.log(.essay)
    }

    func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    /// Asks the on-device model for feedback and turns it into a clean entry.
    static func review(_ text: String, prompt: String) async throws -> WritingEntry {
        let session = LanguageModelSession(instructions: WritingRules.instructions)
        let ask = "Task: \(prompt)\nLearner's text:\n\"\"\"\n\(text)\n\"\"\""
        let c = try await session.respond(to: ask, generating: GeneratedCritique.self).content
        let mistakes = WritingRules.clean(c.mistakes.map { ($0.original, $0.fix, $0.explanationVi) }, in: text)
        return WritingEntry(prompt: prompt, text: text,
                            corrected: WritingRules.correctedText(original: text, model: c.corrected, mistakes: mistakes),
                            mistakes: mistakes, level: WritingRules.level(c.level),
                            summary: c.summaryVi.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func save() {
        guard writable else { return }
        do { try StoreFile.save(entries, to: url, encoder: Self.encoder) } catch { problem = "Không lưu được bài viết: \(error.localizedDescription)" }
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

// MARK: - "Luyện viết" screen

struct WritingView: View {
    let store: WritingStore
    @State private var level = CEFR.b1
    @State private var prompt: WritingPrompt? = WritingPrompt.all.first { $0.level == .b1 }
    @State private var freeTopic = ""
    @State private var text = ""
    @State private var reviewing = false
    @State private var error: String?
    @State private var shown: WritingEntry?
    @FocusState private var editorFocused: Bool

    private var task: String { prompt?.task ?? (freeTopic.isEmpty ? "Free writing" : freeTopic) }

    var body: some View {
        Group {
            if !ExampleWriter.available, store.entries.isEmpty {
                AIUnavailableView()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let p = store.problem { Label(p, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                        if let shown {
                            WritingFeedback(entry: shown) { withAnimation(.smooth) { self.shown = nil } }
                        } else {
                            editor
                        }
                        if !store.entries.isEmpty { history }
                    }
                    .padding(24)
                    .frame(maxWidth: 900, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Luyện viết")
        .task {
            if let id = DebugArgs.value("--prompt"), let p = WritingPrompt.all.first(where: { $0.id == id }) { level = p.level; prompt = p }
            if let t = DebugArgs.value("--write") { text = t; await submit() } // screenshots of the feedback
            else if DebugArgs.has("--show-last") { shown = store.entries.first }
        }
    }

    private var editor: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Đề bài").font(.headline)
                    Spacer()
                    Picker("Trình độ", selection: $level) { ForEach(CEFR.allCases) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 240)
                        .onChange(of: level) { prompt = WritingPrompt.all.first { $0.level == level } }
                }
                Picker("Đề bài", selection: $prompt) {
                    ForEach(WritingPrompt.all.filter { $0.level == level }) { Text($0.title).tag(Optional($0)) }
                    Text("Chủ đề tự do").tag(WritingPrompt?.none)
                }
                .labelsHidden()
                if let prompt {
                    Text(prompt.task).font(.title3.weight(.medium)).textSelection(.enabled)
                } else {
                    TextField("Bạn muốn viết về điều gì?", text: $freeTopic).textFieldStyle(.roundedBorder)
                }
                TextEditor(text: $text)
                    .font(.body)
                    .frame(minHeight: 180)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(editorFocused ? Color.parley.opacity(0.6) : Color.primary.opacity(0.1)))
                    .focused($editorFocused)
                    .accessibilityLabel("Bài viết của bạn")
                    .disabled(reviewing)
                HStack {
                    let n = WritingRules.wordCount(text)
                    Text("\(n) từ").monospacedDigit()
                        .foregroundStyle(n > WritingRules.maxWords ? Color.red : n < WritingRules.minWords ? Color.secondary : Color.green)
                    if let p = WritingRules.problem(with: text), !text.isEmpty { Text("· \(p)").foregroundStyle(.secondary) }
                    Spacer()
                    if reviewing { ProgressView().controlSize(.small) }
                    Button { Task { await submit() } } label: { Label(reviewing ? "Đang chấm…" : "Nhận xét", systemImage: "sparkles") }
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(reviewing || WritingRules.problem(with: text) != nil || !ExampleWriter.available)
                        .help("AI trên máy sửa lỗi và giải thích (⌘↩)")
                }
                .font(.callout)
                if let error { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
            }
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bài đã viết").font(.title3.weight(.semibold))
            ForEach(store.entries) { e in
                Button { withAnimation(.smooth) { shown = e } } label: {
                    HStack(spacing: 12) {
                        Text(e.level).font(.headline).foregroundStyle(Color.parley).frame(width: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.prompt).lineLimit(1)
                            Text("\(e.date.formatted(date: .abbreviated, time: .shortened)) · \(e.mistakes.count) lỗi · \(WritingRules.wordCount(e.text)) từ")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary).accessibilityHidden(true)
                    }
                    .padding(12)
                    .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .contextMenu { Button("Xoá", systemImage: "trash", role: .destructive) { store.remove(e.id) } }
            }
        }
    }

    private func submit() async {
        guard WritingRules.problem(with: text) == nil, !reviewing else { return }
        reviewing = true
        error = nil
        defer { reviewing = false }
        do {
            let entry = try await WritingStore.review(text, prompt: task)
            store.add(entry)
            withAnimation(.smooth) { shown = entry; text = "" }
        } catch {
            self.error = "AI chưa chấm được: \(error.localizedDescription). Bài của bạn vẫn còn nguyên — thử lại nhé."
        }
    }
}

struct WritingFeedback: View {
    let entry: WritingEntry
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                BackButton(title: "Viết bài mới", action: onBack)
                Spacer()
                Text("Trình độ ước tính").foregroundStyle(.secondary)
                Text(entry.level).font(.title2.weight(.bold)).foregroundStyle(Color.parley)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Color.parley.opacity(0.12), in: Capsule())
                    .accessibilityLabel("Trình độ ước tính \(entry.level)")
            }
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text(entry.prompt).font(.headline)
                    if !entry.summary.isEmpty { Label(entry.summary, systemImage: "text.bubble").foregroundStyle(.secondary) }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Bản đã sửa").font(.headline)
                    DiffText(tokens: WordDiff.diff(expected: entry.corrected, typed: entry.text))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                    HStack(spacing: 14) {
                        LegendDot(color: .green, text: "giữ nguyên")
                        LegendDot(color: .red, text: "đã sửa (bạn viết)")
                        LegendDot(color: .orange, text: "thêm vào")
                        LegendDot(color: .secondary, text: "bỏ đi")
                    }
                    .font(.caption)
                }
            }
            Label("Nhận xét do AI chạy trên máy đưa ra — đôi khi bỏ sót hoặc sửa chưa đúng; hãy đối chiếu với bài Ngữ pháp khi thấy lạ.",
                  systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary)
            if entry.mistakes.isEmpty {
                Label("Không tìm thấy lỗi đáng kể — rất tốt!", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            } else {
                Text("Lỗi cần nhớ (\(entry.mistakes.count))").font(.title3.weight(.semibold))
                ForEach(entry.mistakes, id: \.self) { m in
                    Card(padding: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(m.original).strikethrough().foregroundStyle(.red)
                                Image(systemName: "arrow.right").foregroundStyle(.secondary).accessibilityHidden(true)
                                Text(m.fix).fontWeight(.semibold).foregroundStyle(.green)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(m.original) sửa thành \(m.fix)")
                            if !m.explanation.isEmpty { Text(m.explanation).font(.callout).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
        }
    }
}
