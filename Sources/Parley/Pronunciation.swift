import Observation
import Speech
import SwiftUI

/// How clearly the recognizer heard one word the user said into the microphone.
struct SpokenWord: Codable, Identifiable, Hashable {
    var id: String { word }
    var word: String
    var language: String           // speech locale, e.g. "en_US"
    var heard = 0
    var unclear = 0                // times its confidence was below `PronunciationStore.unclearBelow`
    var fixed = 0                  // successful retries in the "Phát âm của tôi" tab
    var confidenceSum = 0.0
    var lastHeard = Date()
    var examples: [String] = []    // sentences where it was unclear, newest first (max 3)
    var streak: Int?               // correct retries in a row (optional: older files lack it)

    var clarity: Double { heard == 0 ? 1 : confidenceSum / Double(heard) }
    var open: Int { max(0, unclear - fixed) }
}

/// Collects per-word recognizer confidence from the user's own speech (mic) across sessions.
/// Stored in ~/Documents/Parley/pronunciation.json.
@Observable @MainActor
final class PronunciationStore {
    private(set) var words: [String: SpokenWord] = [:]
    /// Even clean synthetic speech scores ~0.65 on some words, so only clearly uncertain words count.
    static let unclearBelow = 0.5
    @ObservationIgnored private let url: URL

    init(file: URL = Model.dataDir.appending(path: "pronunciation.json")) {
        url = file
        guard let data = try? Data(contentsOf: url) else { return }
        do {
            words = try Self.decoder.decode([String: SpokenWord].self, from: data)
        } catch {
            try? FileManager.default.moveItem(at: url, to: url.deletingPathExtension().appendingPathExtension("unreadable.json"))
        }
    }

    func record(_ text: AttributedString, language: String) {
        let sentence = String(text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        var changed = false
        for run in text.runs {
            guard let confidence = run.transcriptionConfidence else { continue }
            for w in Answer.normalize(String(text[run.range].characters)).split(separator: " ").map(String.init) where w.count >= 2 {
                var s = words[w] ?? SpokenWord(word: w, language: language)
                s.heard += 1
                s.confidenceSum += confidence
                s.lastHeard = .now
                if confidence < Self.unclearBelow {
                    s.unclear += 1
                    if !s.examples.contains(sentence) { s.examples = Array(([sentence] + s.examples).prefix(3)) }
                }
                words[w] = s
                changed = true
            }
        }
        if changed { save() }
    }

    /// Words with unclear moments not yet fixed, worst first.
    var needsWork: [SpokenWord] {
        words.values.filter { $0.open > 0 }.sorted { ($0.open, -$0.clarity) > ($1.open, -$1.clarity) }
    }

    var overallClarity: Double {
        let heard = words.values.reduce(0) { $0 + $1.heard }
        return heard == 0 ? 1 : words.values.reduce(0) { $0 + $1.confidenceSum } / Double(heard)
    }

    static let streakToClear = 3

    /// Retry result. The word leaves the list only after `streakToClear` correct reads in a row; a miss resets the count.
    @discardableResult
    func retry(_ word: String, correct: Bool) -> Int {
        guard var s = words[word] else { return 0 }
        s.streak = correct ? (s.streak ?? 0) + 1 : 0
        if (s.streak ?? 0) >= Self.streakToClear {
            s.fixed = s.unclear
            s.streak = 0
        }
        words[word] = s
        save()
        return s.streak ?? 0
    }

    func forget(_ word: String) {
        words[word] = nil
        save()
    }

    private func save() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Self.encoder.encode(words).write(to: url, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

/// ●●○ progress toward the 3-in-a-row goal.
struct StreakDots: View {
    let count: Int
    let total: Int
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<total, id: \.self) { i in
                Circle().fill(i < count ? Color.green : Color.secondary.opacity(0.3)).frame(width: 7, height: 7)
            }
        }
        .animation(.snappy, value: count)
        .help("Đọc đúng liên tiếp \(count)/\(total) lần")
    }
}

// MARK: - Tab

struct PronunciationView: View {
    let store: PronunciationStore
    let vocab: VocabStore
    let target: Locale.Language
    @State private var mic = MicCheck()
    @State private var active: String?
    @State private var results: [String: Bool] = [:]
    @Environment(ActivityStore.self) private var activity

    var body: some View {
        Group {
            if store.words.isEmpty {
                ContentUnavailableView {
                    Label("Chưa có dữ liệu giọng nói", systemImage: "waveform.badge.mic")
                } description: {
                    Text("Bật Micro rồi nói trong lúc phiên dịch. Parley sẽ đánh dấu những từ máy nghe chưa rõ để bạn luyện lại.")
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 14) {
                            StatTile(value: store.words.count, title: "Từ bạn đã nói", symbol: "text.bubble", color: .parley)
                            StatTile(value: Int((store.overallClarity * 100).rounded()), title: "Độ rõ trung bình (%)", symbol: "waveform", color: .green)
                            StatTile(value: store.needsWork.count, title: "Từ cần luyện lại", symbol: "exclamationmark.bubble", color: .orange)
                        }
                        Label("Máy chấm độ chắc chắn cho từng từ bạn nói qua micro. Từ bị nghe “không chắc” nhiều lần thường do phát âm, đôi khi do tiếng ồn hoặc micro. Đọc lại đúng thì từ được gỡ khỏi danh sách.",
                              systemImage: "info.circle")
                            .font(.callout).foregroundStyle(.secondary)
                        if store.needsWork.isEmpty {
                            Label("Tuyệt! Chưa có từ nào cần luyện lại.", systemImage: "checkmark.seal.fill")
                                .font(.title3.weight(.semibold)).foregroundStyle(.green)
                                .padding(.top, 8)
                        }
                        ForEach(store.needsWork) { w in row(w).transition(.move(edge: .leading).combined(with: .opacity)) }
                    }
                    .padding(24)
                    .frame(maxWidth: 900, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .animation(.smooth, value: store.needsWork.map(\.word))
                }
            }
        }
        .navigationTitle("Phát âm của tôi")
    }

    private func row(_ w: SpokenWord) -> some View {
        let lang = Locale(identifier: w.language).language
        let listening = mic.listening && active == w.word
        return HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(w.word).font(.title2.weight(.bold))
                    if let ipa = Pronunciation.ipa(w.word, language: lang) { Text(ipa).foregroundStyle(.secondary) }
                }
                HStack(spacing: 10) {
                    Gauge(value: w.clarity) { EmptyView() }
                        .gaugeStyle(.accessoryLinearCapacity)
                        .tint(w.clarity < PronunciationStore.unclearBelow ? .orange : .green)
                        .frame(width: 120)
                    Text("rõ \(Int((w.clarity * 100).rounded()))% · chưa rõ \(w.open)/\(w.heard) lần")
                        .font(.caption).foregroundStyle(.secondary)
                    StreakDots(count: w.streak ?? 0, total: PronunciationStore.streakToClear)
                }
                if let example = w.examples.first {
                    Text(highlight(example, w.word)).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                }
                if listening {
                    Label("Đang nghe… đọc to “\(w.word)”", systemImage: "waveform").foregroundStyle(Color.parley)
                        .symbolEffect(.variableColor.iterative)
                } else if let ok = results[w.word] {
                    Label(ok ? "Đúng! Đọc đúng \(PronunciationStore.streakToClear) lần liên tiếp để hoàn thành (\(w.streak ?? 0)/\(PronunciationStore.streakToClear))"
                             : "Máy nghe thành “\(mic.heard ?? "")” — đếm lại từ đầu, nghe mẫu rồi thử lại",
                          systemImage: ok ? "checkmark.circle.fill" : "arrow.counterclockwise.circle.fill")
                        .foregroundStyle(ok ? .green : .orange)
                }
                if let error = mic.error, active == w.word { Text(error).font(.callout).foregroundStyle(.red) }
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                SpeakButton { Speaker.speak(w.word, language: lang) }
                Button { Task { await retry(w) } } label: {
                    Image(systemName: listening ? "stop.fill" : "mic.fill").font(.title2).frame(width: 44, height: 44)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(listening ? .red : .parley)
                .disabled(mic.listening && !listening)
                .help("Đọc lại để máy chấm")
                Menu {
                    Button("Thêm vào Từ vựng để luyện", systemImage: "plus") { Task { await addToVocabulary(w) } }
                        .disabled(vocab.contains(w.word))
                    Button("Bỏ qua từ này", systemImage: "eye.slash") { store.forget(w.word) }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuIndicator(.hidden)
                .buttonStyle(.glass)
                .fixedSize()
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }

    private func retry(_ w: SpokenWord) async {
        if mic.listening { return await finish(w) }
        active = w.word
        results[w.word] = nil
        await mic.start(language: w.language)
        try? await Task.sleep(for: .seconds(3))
        if mic.listening, active == w.word { await finish(w) }
    }

    private func finish(_ w: SpokenWord) async {
        let heard = await mic.stop()
        let ok = Answer.score(heard: heard, expected: w.word) >= 1
        activity.add(.speaking, xp: XP.answer(ok))
        if ok, (w.streak ?? 0) + 1 >= PronunciationStore.streakToClear {
            results[w.word] = true
            Speaker.speak(w.word, language: Locale(identifier: w.language).language)
            try? await Task.sleep(for: .seconds(1.2)) // let the success show before the row leaves
        }
        store.retry(w.word, correct: ok)
        results[w.word] = ok
    }

    private func addToVocabulary(_ w: SpokenWord) async {
        let lang = Locale(identifier: w.language).language
        let example = w.examples.first ?? ""
        let meaning = await Translator.translate(w.word, from: lang, to: target) ?? ""
        let exampleTranslation = example.isEmpty ? "" : (await Translator.translate(example, from: lang, to: target) ?? "")
        vocab.add(VocabItem(term: w.word, meaning: meaning, termLanguage: lang.maximalIdentifier,
                            meaningLanguage: target.minimalIdentifier, ipa: Pronunciation.ipa(w.word, language: lang),
                            example: example, exampleTranslation: exampleTranslation, session: nil))
    }

    private func highlight(_ s: String, _ word: String) -> AttributedString {
        var a = AttributedString(s)
        if let r = a.range(of: word, options: .caseInsensitive) {
            a[r].foregroundColor = .orange
            a[r].font = .callout.bold()
        }
        return a
    }
}
