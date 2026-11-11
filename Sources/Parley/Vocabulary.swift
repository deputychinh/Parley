import AVFoundation
import Foundation
import Observation
import Translation

/// One saved word or phrase. Stored as JSON in ~/Documents/Parley/vocabulary.json.
struct VocabItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var term: String               // in the language being learned (what was heard), e.g. "leak"
    var meaning: String            // in the learner's language, e.g. "rò rỉ"
    var termLanguage: String       // BCP-47, e.g. "en-US"
    var meaningLanguage: String    // e.g. "vi"
    var ipa: String?               // English terms only
    var example: String            // sentence the term was heard in
    var exampleTranslation: String
    var session: String?           // session stamp, e.g. 2026-11-05_01-15-12
    var added = Date()
    var mastered = false
    var masteredRank: Int { mastered ? 1 : 0 } // Table sorting needs Comparable

    // Spaced repetition (Leitner boxes). Optional so files saved before this feature still decode.
    var box: Int?          // 0…5; nil = never practiced
    var due: Date?         // next review; nil = due now
    var reviews: Int?
    var correctCount: Int?

    /// Mastered words are due too: they come back at long intervals so they aren't forgotten.
    var isDue: Bool { (due ?? .distantPast) <= .now }
    static let intervals: [Double] = [0, 1, 3, 7, 14, 30, 60, 120] // days to wait in each box
    static let masteredBox = 5 // ≥ 30-day interval

    /// Right → next box (review later); wrong → back to box 0 (review now) and no longer mastered.
    mutating func review(correct ok: Bool, now: Date = .now) {
        reviews = (reviews ?? 0) + 1
        if ok { correctCount = (correctCount ?? 0) + 1 }
        let b = ok ? min((box ?? 0) + 1, Self.intervals.count - 1) : 0
        box = b
        due = now.addingTimeInterval(Self.intervals[b] * 86_400)
        mastered = b >= Self.masteredBox
    }
}

@Observable @MainActor
final class VocabStore {
    private(set) var items: [VocabItem] = []
    private(set) var problem: String?
    @ObservationIgnored private let url: URL
    @ObservationIgnored private var writable = true
    @ObservationIgnored private let activity: ActivityStore?

    init(file: URL = Model.dataDir.appending(path: "vocabulary.json"), activity: ActivityStore? = nil) {
        url = file
        self.activity = activity
        let loaded = StoreFile.load([VocabItem].self, from: url, decoder: Self.decoder)
        items = loaded.value ?? []
        writable = loaded.writable
        problem = loaded.problem
    }

    var learning: Int { items.count { !$0.mastered } }
    var dueCount: Int { items.count { $0.isDue } }

    /// Spaced-repetition step for one card; also logs XP (`spoken` = a pronunciation card).
    func review(_ id: UUID, correct: Bool, spoken: Bool = false) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].review(correct: correct)
        save()
        activity?.log(.review(ok: correct, spoken: spoken))
    }

    func contains(_ term: String) -> Bool {
        items.contains { $0.term.caseInsensitiveCompare(term) == .orderedSame }
    }

    func add(_ item: VocabItem) {
        guard !contains(item.term) else { return }
        items.insert(item, at: 0)
        save()
    }

    /// Adds many words with one save (import); words already present are skipped. Returns how many were saved
    /// (0 when the store is read-only or the save failed, so the import never claims words it didn't keep).
    @discardableResult func addMany(_ new: [VocabItem]) -> Int {
        guard writable else { return 0 }
        var known = Set(items.map { $0.term.lowercased() })
        let fresh = new.filter { known.insert($0.term.lowercased()).inserted }
        guard !fresh.isEmpty else { return 0 }
        let before = items
        items.insert(contentsOf: fresh, at: 0)
        problem = nil
        save()
        guard problem == nil else { items = before; return 0 } // the save failed: keep memory and file in step
        return fresh.count
    }

    func remove(_ ids: Set<UUID>) {
        items.removeAll { ids.contains($0.id) }
        save()
    }

    func setMastered(_ ids: Set<UUID>, _ value: Bool) {
        for i in items.indices where ids.contains(items[i].id) {
            items[i].mastered = value
            items[i].box = value ? VocabItem.masteredBox : 0
            items[i].due = value ? Date.now.addingTimeInterval(VocabItem.intervals[VocabItem.masteredBox] * 86_400) : nil
        }
        save()
    }

    private func save() {
        guard writable else { return }
        do { try StoreFile.save(items, to: url, encoder: Self.encoder) } catch { problem = "Không lưu được từ vựng: \(error.localizedDescription)" }
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

/// Offline text-to-speech with the system voices.
@MainActor
enum Speaker {
    private static let synth = AVSpeechSynthesizer()

    static func stop() { synth.stopSpeaking(at: .immediate) }
    static var isSpeaking: Bool { synth.isSpeaking }

    /// `speed` multiplies the user's reading rate (Settings), e.g. 0.75 in listening practice.
    static func speak(_ text: String, language: Locale.Language, speed: Double = 1) {
        synth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        let code = language.languageCode?.identifier ?? "en"
        u.voice = language.region.flatMap { AVSpeechSynthesisVoice(language: "\(code)-\($0.identifier)") }
            ?? AVSpeechSynthesisVoice.speechVoices().first { $0.language.hasPrefix(code) }
        let rate = AppDefaults.store.object(forKey: "speechRate") as? Double ?? 0.85
        u.rate = AVSpeechUtteranceDefaultSpeechRate * Float(rate * speed)
        synth.speak(u)
    }
}

/// On-demand translation of selected text, either direction, using installed language packs only.
@MainActor
enum Translator {
    private static var sessions: [String: TranslationSession] = [:]

    static func translate(_ text: String, from: Locale.Language, to: Locale.Language) async -> String? {
        let key = "\(from.minimalIdentifier)>\(to.minimalIdentifier)"
        if sessions[key] == nil {
            guard await LanguageAvailability().status(from: from, to: to) == .installed else { return nil }
            sessions[key] = TranslationSession(installedSource: from, target: to)
        }
        return try? await sessions[key]?.translate(text).targetText
    }
}

/// American-English IPA from the CMU Pronouncing Dictionary (bundled, offline).
enum Pronunciation {
    private static let dict: [String: String] = {
        let url = Bundle.main.url(forResource: "cmudict", withExtension: "dict") ?? URL(fileURLWithPath: "Resources/cmudict.dict")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var d: [String: String] = [:]
        d.reserveCapacity(140_000)
        for line in text.split(separator: "\n") {
            guard let space = line.firstIndex(of: " ") else { continue }
            let word = line[..<space]
            if word.hasSuffix(")") { continue } // "word(2)" = alternate pronunciation; keep the first
            var phones = line[line.index(after: space)...]
            if let hash = phones.firstIndex(of: "#") { phones = phones[..<hash] }
            d[String(word)] = phones.trimmingCharacters(in: .whitespaces)
        }
        return d
    }()

    /// "/həˈloʊ/" for "hello"; nil when no word is known or the language isn't English.
    static func ipa(_ text: String, language: Locale.Language) -> String? {
        language.languageCode == .english ? ipa(text) : nil
    }

    static func ipa(_ text: String) -> String? {
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.letters.union(CharacterSet(charactersIn: "'")).inverted)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }
        // Unknown words (names, slang) keep their spelling so the rest of a sentence still gets IPA.
        let out = words.map { w in dict[w].map(convert) ?? w }
        guard words.contains(where: { dict[$0] != nil }) else { return nil }
        return "/" + out.joined(separator: " ") + "/"
    }

    /// CMUdict phones of one word, ARPAbet with stress digits ("SHIH1P"→ ["SH", "IH1", "P"]); nil when unknown.
    static func phones(_ word: String) -> [String]? {
        dict[word.lowercased()].map { $0.split(separator: " ").map(String.init) }
    }

    /// One ARPAbet phone ("AH0", "SH") as IPA ("ə", "ʃ"), the way `ipa(_:)` writes it.
    static func symbol(_ phone: String) -> String {
        var base = phone
        let stress = base.last.flatMap { $0.isNumber ? $0 : nil }
        if stress != nil { base.removeLast() }
        if stress == "0", base == "AH" { return "ə" }
        if stress == "0", base == "ER" { return "ɚ" }
        return map[base] ?? base.lowercased()
    }

    private static let map: [String: String] = [
        "AA": "ɑ", "AE": "æ", "AH": "ʌ", "AO": "ɔ", "AW": "aʊ", "AY": "aɪ", "B": "b", "CH": "tʃ", "D": "d", "DH": "ð",
        "EH": "ɛ", "ER": "ɝ", "EY": "eɪ", "F": "f", "G": "ɡ", "HH": "h", "IH": "ɪ", "IY": "i", "JH": "dʒ", "K": "k",
        "L": "l", "M": "m", "N": "n", "NG": "ŋ", "OW": "oʊ", "OY": "ɔɪ", "P": "p", "R": "ɹ", "S": "s", "SH": "ʃ",
        "T": "t", "TH": "θ", "UH": "ʊ", "UW": "u", "V": "v", "W": "w", "Y": "j", "Z": "z", "ZH": "ʒ",
    ]

    private static func convert(_ arpabet: String) -> String {
        var syms: [String] = [], vowel: [Bool] = [], marks: [(Int, String)] = []
        for ph in arpabet.split(separator: " ") {
            var base = String(ph)
            var stress: Character?
            if let last = base.last, last.isNumber { stress = last; base.removeLast() }
            var ipa = map[base] ?? base.lowercased()
            if stress == "0", base == "AH" { ipa = "ə" }
            if stress == "0", base == "ER" { ipa = "ɚ" }
            if stress == "1" || stress == "2" { marks.append((syms.count, stress == "1" ? "ˈ" : "ˌ")) }
            syms.append(ipa)
            vowel.append(stress != nil)
        }
        guard vowel.count(where: { $0 }) > 1 else { return syms.joined() } // no stress mark on one-syllable words
        // shortcut: stress goes before the whole onset at word start, else before one consonant; good enough for learners.
        for (v, mark) in marks.reversed() {
            let j = !vowel[..<v].contains(true) ? 0 : (v > 0 && !vowel[v - 1] ? v - 1 : v)
            syms.insert(mark, at: j)
            vowel.insert(false, at: j)
        }
        return syms.joined()
    }
}
