import AVFoundation
import SwiftUI

// MARK: - "Luyện âm": minimal pairs for Vietnamese speakers (PARLEY-33)

/// Words that differ in one sound, practised together: hear which one was said, then say each one.
struct ContrastSet: Identifiable, Hashable {
    let id: String
    let title: String
    let why: String
    /// Lessons (IPASound ids) this set trains.
    let sounds: [String]
    let priority: IPASound.Priority
    /// Each item: 2–3 words that differ in the trained sound.
    let items: [[String]]

    var words: [String] { items.flatMap { $0 } }

    /// Words the on-device recognizer turns into their common partner whatever the voice (`--sound-eval`,
    /// 2026-11-12: den → then, doze → those, dare → there, dough → go, berry → very): heard in "Nghe", never
    /// asked for in "Nói", where the learner would be marked wrong for a right sound.
    nonisolated static let hearOnly: Set<String> = ["den", "doze", "dare", "dough", "berry"]

    /// What "Nói" asks the learner to say.
    var sayable: [String] { words.filter { !Self.hearOnly.contains($0) } }

    /// The carrier the learner says: single words alone are often misrecognized (spike 2026-11-12).
    nonisolated static func carrier(_ word: String) -> String { "I said \(word) again." }

    /// Ordered by what most hurts being understood (brief.md).
    static let all: [ContrastSet] = [
        .init(id: "finals", title: "Âm cuối /t/ /d/ /k/ /p/", why: "Người Việt hay nuốt âm cuối; mất âm cuối là mất cả từ: see – seat – seed.",
              sounds: ["T", "D", "K", "P"], priority: .high,
              items: [["see", "seat", "seed"], ["bye", "bite", "bike"], ["lie", "light", "like"], ["row", "road", "rope"],
                      ["way", "wait", "wake"], ["tie", "tight", "tide"]]),
        .init(id: "endings", title: "Đuôi -s và -ed", why: "Đuôi -s (số nhiều, ngôi thứ ba) và -ed (quá khứ) mang nghĩa ngữ pháp; bỏ đi là nói sai thì, sai số.",
              sounds: ["S", "Z", "D", "T"], priority: .high,
              items: [["work", "works", "worked"], ["play", "plays", "played"], ["help", "helps", "helped"],
                      ["walk", "walks", "walked"], ["call", "calls", "called"], ["like", "likes", "liked"]]),
        .init(id: "clusters", title: "Cụm phụ âm đầu", why: "Tiếng Việt không có cụm phụ âm; bỏ bớt một âm là thành từ khác: play → pay.",
              sounds: ["L", "R"], priority: .high,
              items: [["pay", "play"], ["fight", "flight"], ["bed", "bread"], ["tick", "trick"], ["cap", "clap"], ["gas", "glass"]]),
        .init(id: "s-sh", title: "/s/ – /ʃ/", why: "“x” tiếng Việt nằm giữa hai âm này; nhầm là thành từ khác: sip – ship.",
              sounds: ["S", "SH"], priority: .high,
              items: [["sip", "ship"], ["see", "she"], ["sell", "shell"], ["sort", "short"], ["save", "shave"], ["seat", "sheet"]]),
        .init(id: "i-length", title: "/i/ dài – /ɪ/ ngắn", why: "Độ dài nguyên âm đổi nghĩa: leave – live, feel – fill.",
              sounds: ["IY", "IH"], priority: .high,
              items: [["sheep", "ship"], ["seat", "sit"], ["leave", "live"], ["feel", "fill"], ["heat", "hit"], ["eat", "it"]]),
        .init(id: "l-n", title: "/l/ – /n/", why: "Một số vùng ở Việt Nam lẫn “l” và “n”: light – night.",
              sounds: ["L", "N"], priority: .normal,
              items: [["light", "night"], ["low", "no"], ["lot", "not"], ["line", "nine"], ["lock", "knock"], ["lap", "nap"]]),
        .init(id: "v-b-w", title: "/v/ – /b/ – /w/", why: "Mím môi (/b/) hay tròn môi (/w/) thay cho răng chạm môi (/v/): very – berry.",
              sounds: ["V", "B", "W"], priority: .normal,
              items: [["very", "berry"], ["vest", "west"], ["van", "ban"], ["vet", "bet"], ["vote", "boat"], ["vine", "wine"]]),
        .init(id: "th-s-t", title: "/θ/ – /s/ – /t/", why: "Ít ảnh hưởng việc được hiểu hơn các nhóm trên — luyện sau: think – sink.",
              sounds: ["TH", "S", "T"], priority: .low,
              items: [["think", "sink"], ["thank", "tank"], ["three", "tree"], ["thin", "tin"], ["path", "pass"], ["mouth", "mouse"]]),
        .init(id: "dh-d", title: "/ð/ – /d/", why: "Ít ảnh hưởng việc được hiểu — luyện sau: they – day.",
              sounds: ["DH", "D"], priority: .low,
              items: [["they", "day"], ["then", "den"], ["though", "dough"], ["there", "dare"], ["breathe", "breed"], ["those", "doze"]]),
    ]

    static func set(_ id: String) -> ContrastSet? { all.first { $0.id == id } }

    /// Recognizer hints for saying `word`: every word of its item (the pair), so rare words (den, doze) are not
    /// heard as their common partner just for being rare — and neither side is favoured.
    func context(for word: String) -> [String] {
        let item = items.first { $0.contains(word) } ?? [word]
        return item.flatMap { [$0, Self.carrier($0)] }
    }
    static func sets(for sound: String) -> [ContrastSet] { all.filter { $0.sounds.contains(sound) } }
}

/// What the recognizer heard against the word the learner meant, sound by sound (CMUdict, stress ignored).
enum SoundDiff {
    enum Change: Equatable {
        case swapped(String, String)  // target phone → heard phone
        case missing(String)          // target phone not heard
        case extra(String)            // heard phone not in the target
    }

    struct Result: Equatable {
        /// What the recognizer wrote in the slot (nil: the carrier was not understood).
        let heard: String?
        let same: Bool
        let changes: [Change]
    }

    /// The words between "said" and "again" in "I said ___ again.", lower-cased; nil when the carrier is not there.
    /// The recognizer writes small numbers as digits ("I said 9 again."): back to words before comparing.
    nonisolated static let numbers = ["0": "zero", "1": "one", "2": "two", "3": "three", "4": "four", "5": "five",
                                      "6": "six", "7": "seven", "8": "eight", "9": "nine", "10": "ten"]

    nonisolated static func words(_ text: String) -> [String] {
        Answer.normalize(text).split(separator: " ").map { numbers[String($0)] ?? String($0) }
    }

    nonisolated static func slot(in text: String) -> String? {
        let words = words(text)
        guard let said = words.lastIndex(of: "said") else { return nil }
        let rest = words[(said + 1)...]
        let end = rest.firstIndex(of: "again") ?? rest.endIndex
        let slot = rest[..<end].joined(separator: " ")
        return slot.isEmpty ? nil : slot
    }

    nonisolated static func bare(_ phones: [String]) -> [String] { phones.map { $0.filter { !$0.isNumber } } }

    /// Same sounds = right, even when spelled otherwise (bye = buy, write = right).
    static func compare(target: String, said text: String) -> Result {
        guard let slot = slot(in: text) else {
            // No carrier recognized: accept only the word itself said alone.
            let words = words(text)
            if words.count == 1, let w = words.first { return compare(target: target, slot: w) }
            return Result(heard: nil, same: false, changes: [])
        }
        return compare(target: target, slot: slot)
    }

    static func compare(target: String, slot: String) -> Result {
        let want = bare(Pronunciation.phones(target) ?? [])
        let got = bare(slot.split(separator: " ").flatMap { Pronunciation.phones(String($0)) ?? [] })
        if !want.isEmpty, want == got { return Result(heard: slot, same: true, changes: []) }
        if slot == target.lowercased() { return Result(heard: slot, same: true, changes: []) }
        return Result(heard: slot, same: false, changes: got.isEmpty ? [] : align(want, got))
    }

    /// Edit script from `a` (target) to `b` (heard), substitutions preferred over a missing + extra pair.
    nonisolated static func align(_ a: [String], _ b: [String]) -> [Change] {
        let n = a.count, m = b.count
        var d = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 0...n { d[i][0] = i }
        for j in 0...m { d[0][j] = j }
        if n > 0, m > 0 {
            for i in 1...n {
                for j in 1...m {
                    d[i][j] = min(d[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1), d[i - 1][j] + 1, d[i][j - 1] + 1)
                }
            }
        }
        var out: [Change] = []
        var i = n, j = m
        while i > 0 || j > 0 {
            if i > 0, j > 0, d[i][j] == d[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1) {
                if a[i - 1] != b[j - 1] { out.append(.swapped(a[i - 1], b[j - 1])) }
                i -= 1; j -= 1
            } else if i > 0, d[i][j] == d[i - 1][j] + 1 {
                out.append(.missing(a[i - 1])); i -= 1
            } else {
                out.append(.extra(b[j - 1])); j -= 1
            }
        }
        return out.reversed()
    }

    /// "âm /ʃ/ thành /s/ · thiếu âm /t/" for the feedback line.
    nonisolated static func describe(_ changes: [Change]) -> String {
        changes.map {
            switch $0 {
            case .swapped(let a, let b): "âm /\(Pronunciation.symbol(a + "1"))/ thành /\(Pronunciation.symbol(b + "1"))/"
            case .missing(let a): "thiếu âm /\(Pronunciation.symbol(a + "1"))/"
            case .extra(let b): "thừa âm /\(Pronunciation.symbol(b + "1"))/"
            }
        }
        .joined(separator: " · ")
    }
}

/// One contrast set's record: hearing and saying trials. Stored in `sounds.json`:
/// `{ "finals": { "heard": 10, "heardRight": 8, "said": 10, "saidRight": 6, "last": "2026-11-12" } }`.
struct SoundStats: Codable, Equatable {
    var heard = 0, heardRight = 0, said = 0, saidRight = 0
    var last = ""   // yyyy-MM-dd (local) of the last trial

    var saidRate: Double { said == 0 ? 0 : Double(saidRight) / Double(said) }
    var heardRate: Double { heard == 0 ? 0 : Double(heardRight) / Double(heard) }
    /// A set counts as passed after 10 spoken trials at 80 % or better.
    var passed: Bool { said >= 10 && saidRate >= 0.8 }
}

@Observable @MainActor
final class SoundStore {
    private(set) var stats: [String: SoundStats] = [:]
    private(set) var problem: String?
    @ObservationIgnored private let url: URL
    @ObservationIgnored private var writable = true
    @ObservationIgnored private let activity: ActivityStore?

    init(file: URL = Model.dataDir.appending(path: "sounds.json"), activity: ActivityStore? = nil) {
        url = file
        self.activity = activity
        let loaded = StoreFile.load([String: SoundStats].self, from: url)
        stats = loaded.value ?? [:]
        writable = loaded.writable
        problem = loaded.problem
    }

    /// A hearing trial: listening XP. A saying trial: speaking XP (10 right, 2 for trying).
    func record(_ set: String, saying: Bool, right: Bool, now: Date = .now) {
        var s = stats[set] ?? SoundStats()
        if saying { s.said += 1; if right { s.saidRight += 1 } } else { s.heard += 1; if right { s.heardRight += 1 } }
        s.last = StudyStore.day(now)
        stats[set] = s
        activity?.log(saying ? .pronunciation(ok: right) : .listening(dictation: true, pass: right), now: now)
        save()
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    /// The next set to practise: the first by priority not yet passed.
    var next: ContrastSet? { ContrastSet.all.first { !(stats[$0.id]?.passed ?? false) } }

    private func save() {
        guard writable else { return }
        do { try StoreFile.save(stats, to: url, encoder: Self.encoder) } catch { problem = "Không lưu được kết quả luyện âm: \(error.localizedDescription)" }
    }
}

/// Model voices for "Nghe": several installed English voices (high-variability training), else the default one.
enum ModelVoices {
    static func english() -> [AVSpeechSynthesisVoice] {
        var seen = Set<String>()
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en-") && !$0.voiceTraits.contains(.isNoveltyVoice) }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
            .filter { seen.insert($0.language).inserted } // one voice per accent: US, GB, AU, IE…
    }
}

// MARK: - The lab: 10 × "Nghe", then 10 × "Nói"

/// One round's trials, drawn up front so the order is testable.
struct LabRound: Equatable {
    struct Trial: Equatable { let options: [String]; let target: String; let voice: Int }
    let hear: [Trial]
    let say: [String]

    static let length = 10

    /// `voices`: how many model voices to rotate through (at least 1).
    static func make<G: RandomNumberGenerator>(_ set: ContrastSet, voices: Int, using rng: inout G) -> LabRound {
        let n = max(voices, 1)
        let hear = (0..<length).map { i -> Trial in
            let item = set.items.randomElement(using: &rng)!
            return Trial(options: item, target: item.randomElement(using: &rng)!, voice: i % n)
        }
        var words = set.sayable.shuffled(using: &rng)
        while words.count < length { words += set.sayable.shuffled(using: &rng) }
        return LabRound(hear: hear, say: Array(words.prefix(length)))
    }
}

struct SoundLabView: View {
    let set: ContrastSet
    let store: SoundStore
    let openLesson: (IPASound) -> Void
    let back: () -> Void

    private enum Step: Equatable { case hear(Int), say(Int), done }
    @State private var round: LabRound
    @State private var step = Step.hear(0)
    @State private var chosen: String?
    @State private var outcome: SoundDiff.Result?
    @State private var hearRight = 0
    @State private var sayRight = 0
    @State private var mic = MicCheck()
    private let voices = ModelVoices.english()

    init(set: ContrastSet, store: SoundStore, openLesson: @escaping (IPASound) -> Void, back: @escaping () -> Void) {
        self.set = set
        self.store = store
        self.openLesson = openLesson
        self.back = back
        var rng = SystemRandomNumberGenerator()
        _round = State(initialValue: LabRound.make(set, voices: ModelVoices.english().count, using: &rng))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    BackButton(title: "Âm tiếng Anh", action: { Task { _ = await mic.stop(); mic.reset() }; back() })
                    Text(set.title).font(.headline)
                    Spacer()
                    Text(progressText).monospacedDigit().foregroundStyle(.secondary)
                }
                ProgressView(value: progress).tint(.parley)
                Group {
                    switch step {
                    case .hear(let i): hearCard(round.hear[i])
                    case .say(let i): sayCard(round.say[i])
                    case .done: summary
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task(id: step) { if case .hear(let i) = step { try? await Task.sleep(for: .milliseconds(300)); play(round.hear[i]) } }
        .onDisappear { Task { _ = await mic.stop(); mic.reset() } }
    }

    private var progress: Double {
        switch step {
        case .hear(let i): Double(i) / Double(2 * LabRound.length)
        case .say(let i): Double(LabRound.length + i) / Double(2 * LabRound.length)
        case .done: 1
        }
    }

    private var progressText: String {
        switch step {
        case .hear(let i): "Nghe \(i + 1)/\(LabRound.length)"
        case .say(let i): "Nói \(i + 1)/\(LabRound.length)"
        case .done: "Xong"
        }
    }

    private func voice(_ index: Int) -> AVSpeechSynthesisVoice? { voices.isEmpty ? nil : voices[index % voices.count] }

    private func play(_ trial: LabRound.Trial) { Speaker.speak(trial.target, voice: voice(trial.voice)) }

    // MARK: Nghe

    private func hearCard(_ trial: LabRound.Trial) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Nghe rồi chọn từ bạn nghe được", systemImage: "ear").font(.title3.weight(.semibold))
            HStack(spacing: 12) {
                Button { play(trial) } label: { Label("Nghe lại", systemImage: "speaker.wave.2.fill") }
                    .buttonStyle(.glass)
                    .keyboardShortcut("r", modifiers: .option)
                    .help("Nghe lại (⌥R)")
                Text(voices.count > 1 ? "Mỗi lần một giọng khác (\(voice(trial.voice)?.name ?? ""))" : "Cài thêm giọng tiếng Anh trong Cài đặt → Trợ năng → Nội dung được đọc để luyện với nhiều giọng")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                ForEach(Array(trial.options.enumerated()), id: \.offset) { i, word in
                    let tint: Color = chosen == nil ? .parley : word == trial.target ? .green : word == chosen ? .red : .secondary
                    Button { choose(word, trial) } label: {
                        VStack(spacing: 4) {
                            Text("\(i + 1)").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                            Text(word).font(.title2.weight(.semibold))
                            Text(Pronunciation.ipa(word) ?? "").font(.callout).foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity)
                        .background(tint.opacity(chosen == nil ? 0.08 : 0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(tint.opacity(0.4)))
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(chosen != nil)
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [])
                }
            }
            if let chosen {
                HStack(spacing: 10) {
                    Label(chosen == trial.target ? "Đúng!" : "Từ được đọc là “\(trial.target)”",
                          systemImage: chosen == trial.target ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.headline).foregroundStyle(chosen == trial.target ? .green : .red)
                    Spacer()
                    ForEach(trial.options, id: \.self) { w in
                        Button(w) { Speaker.speak(w, voice: voice(trial.voice)) }.buttonStyle(.glass)
                    }
                    nextButton
                }
            }
        }
    }

    private func choose(_ word: String, _ trial: LabRound.Trial) {
        guard chosen == nil else { return }
        chosen = word
        let right = word == trial.target
        if right { hearRight += 1 }
        store.record(set.id, saying: false, right: right)
    }

    // MARK: Nói

    private func sayCard(_ word: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Nói cả câu, máy sẽ nghe từ ở giữa", systemImage: "mic").font(.title3.weight(.semibold))
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(word).font(.system(size: 40, weight: .bold))
                Text(Pronunciation.ipa(word) ?? "").font(.title3).foregroundStyle(.secondary)
            }
            Text(ContrastSet.carrier(word)).font(.title2).foregroundStyle(Color.parley)
            HStack(spacing: 14) {
                SpeakButton(shortcut: true, mic: mic) { Speaker.speak(ContrastSet.carrier(word), language: Locale.Language(identifier: "en-US")) }
                Button { Task { await say(word) } } label: {
                    Image(systemName: mic.listening ? "stop.fill" : "mic.fill").font(.system(size: 28)).frame(width: 72, height: 72)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .tint(mic.listening ? .red : .parley)
                .micLevel(mic)
                .disabled(outcome != nil || mic.busy)
                .keyboardShortcut(.space, modifiers: [])
                .help("Nói (Space) — nói xong là tự dừng")
                .accessibilityLabel(mic.listening ? "Dừng" : "Nói")
                MyVoiceButton(mic: mic)
            }
            if mic.listening { Text("Đang nghe… nói “\(ContrastSet.carrier(word))”").foregroundStyle(.secondary) }
            if let error = mic.error { Text(error).font(.callout).foregroundStyle(.red) }
            if let outcome { feedback(outcome, word) }
        }
    }

    @ViewBuilder private func feedback(_ r: SoundDiff.Result, _ word: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if r.same {
                Label("Đúng — máy nghe ra “\(r.heard ?? word)”", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(.green)
            } else if let heard = r.heard {
                Label("Máy nghe ra “\(heard)” \(Pronunciation.ipa(heard) ?? "")", systemImage: "xmark.circle.fill")
                    .font(.headline).foregroundStyle(.red)
                if !r.changes.isEmpty { Text(SoundDiff.describe(r.changes).prefix(1).uppercased() + SoundDiff.describe(r.changes).dropFirst()) }
                if let lesson = Self.lesson(for: r.changes) {
                    Button { openLesson(lesson) } label: { Label("Xem cách phát âm /\(lesson.symbol)/", systemImage: "mouth") }
                        .buttonStyle(.glass)
                }
            }
            HStack {
                if !r.same { Button("Nói lại") { outcome = nil; mic.reset() }.buttonStyle(.glass) }
                Spacer()
                nextButton
            }
        }
    }

    /// The lesson for the first sound that went wrong (the target's sound).
    static func lesson(for changes: [SoundDiff.Change]) -> IPASound? {
        for c in changes {
            switch c {
            case .swapped(let a, _), .missing(let a): if let s = IPASound.of(phone: a + "1") { return s }
            case .extra: continue
            }
        }
        return nil
    }

    private func say(_ word: String) async {
        if mic.listening { return mic.finish() }
        let at = step
        let heard = await mic.listen(language: "en_US", cap: 6, context: set.context(for: word))
        guard step == at, outcome == nil else { return }
        if MicCheck.emptyResultMessage(heard: heard, error: mic.error) != nil {
            if mic.error == nil { mic.error = MicCheck.noSpeech }
            return
        }
        let r = SoundDiff.compare(target: word, said: heard)
        guard r.heard != nil else {
            mic.error = "Chưa nghe rõ — nói lại cả câu “\(ContrastSet.carrier(word))”."
            return
        }
        outcome = r
        if r.same { sayRight += 1 }
        store.record(set.id, saying: true, right: r.same)
    }

    // MARK: Flow

    private var nextButton: some View {
        Button { advance() } label: { Label("Tiếp", systemImage: "arrow.right") }
            .buttonStyle(.glassProminent)
            .keyboardShortcut(.defaultAction)
    }

    private func advance() {
        chosen = nil
        outcome = nil
        mic.reset()
        withAnimation(.smooth) {
            switch step {
            case .hear(let i): step = i + 1 < LabRound.length ? .hear(i + 1) : .say(0)
            case .say(let i): step = i + 1 < LabRound.length ? .say(i + 1) : .done
            case .done: break
            }
        }
    }

    private var summary: some View {
        VStack(spacing: 14) {
            Image(systemName: sayRight >= 8 ? "trophy.fill" : "checkmark.seal.fill").font(.system(size: 56))
                .foregroundStyle(Color.parley.gradient)
            Text("Nghe đúng \(hearRight)/\(LabRound.length) · Nói đúng \(sayRight)/\(LabRound.length)").font(.title2.weight(.bold))
            Text(sayRight >= 8 ? "Tốt lắm! Nhóm âm này đã khá chắc." : "Xem lại cách phát âm rồi luyện thêm một lượt — nghe “Nghe lại giọng tôi” để so với giọng mẫu.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack {
                Button { restart() } label: { Label("Luyện lại", systemImage: "arrow.clockwise") }.buttonStyle(.glass)
                Button(action: back) { Label("Xong", systemImage: "checkmark") }
                    .buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func restart() {
        var rng = SystemRandomNumberGenerator()
        round = LabRound.make(set, voices: voices.count, using: &rng)
        hearRight = 0
        sayRight = 0
        step = .hear(0)
    }
}

// MARK: - `Parley --sound-eval [set]`

/// Says every pair word in the carrier with each installed system voice (`/usr/bin/say`, fixed path, no shell) and
/// checks the on-device recognizer writes it back as itself. Gate: ≥ 90 % for the model accents (US, GB); other
/// accents are reported for information (the recognizer is en_US; a learner aims at a US or UK model).
enum SoundEval {
    /// Human English voices the eval tries, when installed (one per accent); the first two gate.
    nonisolated static let voices = ["Samantha", "Daniel", "Karen", "Moira", "Rishi", "Tessa"]
    nonisolated static let gating: Set<String> = ["Samantha", "Daniel"]

    static func run(only set: String? = nil) async throws -> Bool {
        let installed = try sayVoices()
        let use = voices.filter(installed.contains)
        guard !use.isEmpty else { throw Err("no English say voice installed") }
        let words = Array(Set((set.flatMap(ContrastSet.set).map { [$0] } ?? ContrastSet.all).flatMap(\.sayable))).sorted()
        let dir = FileManager.default.temporaryDirectory.appending(path: "parley-sound-eval-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var ok = true
        for voice in use {
            var right = 0
            var misses: [String] = []
            for word in words {
                let file = dir.appending(path: "\(voice)-\(word).aiff")
                try say(ContrastSet.carrier(word), voice: voice, to: file)
                let set = ContrastSet.all.first { $0.words.contains(word) }
                let heard = try await transcribe(file, context: set?.context(for: word) ?? [])
                if SoundDiff.compare(target: word, said: heard).same { right += 1 } else { misses.append("\(word) → “\(heard)”") }
            }
            let rate = Double(right) / Double(max(words.count, 1))
            let gates = gating.contains(voice)
            print(String(format: "%@: %d/%d (%.0f%%)%@", voice, right, words.count, rate * 100, gates ? "" : " (info)"))
            for m in misses { print("  miss:", m) }
            if gates, rate < 0.9 { ok = false }
        }
        print(ok ? "sound-eval: ok" : "sound-eval: FAIL (< 90% for a US/GB voice)")
        return ok
    }

    private static func sayVoices() throws -> Set<String> {
        let out = try process("/usr/bin/say", ["-v", "?"])
        return Set(out.split(separator: "\n").compactMap { $0.split(separator: " ").first.map(String.init) })
    }

    private static func say(_ text: String, voice: String, to file: URL) throws {
        _ = try process("/usr/bin/say", ["-v", voice, "-o", file.path, text])
    }

    private static func process(_ path: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw Err("\(path) failed (\(p.terminationStatus))") }
        return String(decoding: data, as: UTF8.self)
    }

    private static func transcribe(_ file: URL, context: [String]) async throws -> String {
        let t = try await Transcriber.start(locale: Locale(identifier: "en_US"), context: context)
        let collector = Task {
            var out: [String] = []
            for try await r in t.module.results where r.isFinal { out.append(String(r.text.characters)) }
            return out.joined(separator: " ")
        }
        let audio = try AVAudioFile(forReading: file)
        while audio.framePosition < audio.length {
            guard let buf = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: 4096) else { break }
            try audio.read(into: buf)
            t.feed(buf)
        }
        try await t.finish()
        return try await collector.value.trimmingCharacters(in: .whitespaces)
    }
}
