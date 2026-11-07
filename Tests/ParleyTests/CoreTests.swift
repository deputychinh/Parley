import Foundation
import Testing
@testable import Parley

/// Logic that existed before the learning suite (moved here from the old `--file` precondition block).
@Suite struct SessionFileTests {
    let notes = "# x\n<!-- parley: en_GB > ja -->\n\nGhi âm: a\n\n**10:00:00 AM** 🔊 Hello\n> Xin chào\n\n**10:00:05 AM** 🎤 Bye <!-- t=12.5 -->\n> Tạm biệt\n"

    @Test func parsesBilingualLines() {
        #expect(Model.parse(notes) == [.init(time: "10:00:00 AM", source: .system, en: "Hello", vi: "Xin chào"),
                                       .init(time: "10:00:05 AM", source: .mic, en: "Bye", vi: "Tạm biệt", offset: 12.5)])
    }

    @Test func readsLanguagesWithLegacyDefault() {
        let langs = Model.languages(in: notes)
        #expect(langs.0.region?.identifier == "GB" && langs.1.languageCode == .japanese)
        #expect(Model.languages(in: "old file").1.languageCode == .vietnamese)
    }

    @Test func detectsSpeakerEcho() {
        #expect(Model.isEcho("We need to tell them now.", of: "we need to tell them now"))
        #expect(Model.isEcho("Emma, the system says there's a leak", of: "Emma, the system says there is a leak."))
        #expect(!Model.isEcho("Yes, I agree.", of: "We need to tell them now."))
        #expect(!Model.isEcho("", of: ""))
    }

    @Test func ipaFromCMUdict() {
        #expect(Pronunciation.ipa("hello") == "/həˈloʊ/")
        #expect(Pronunciation.ipa("meeting") == "/ˈmitɪŋ/")
        #expect(Pronunciation.ipa("cat") == "/kæt/")
        #expect(Pronunciation.ipa("xyzzyq") == nil)
        #expect(Pronunciation.ipa("Hello, Xyzzyq!") == "/həˈloʊ xyzzyq/")
    }
}

@Suite struct AnswerTests {
    @Test func matchesIgnoringCaseAndPunctuation() {
        #expect(Answer.matches("  Heritage. ", "heritage"))
        #expect(!Answer.matches("heritag", "heritage"))
        #expect(!Answer.matches("", ""))
    }
    @Test func scoresHeardWords() {
        #expect(Answer.score(heard: "um we need to tell them now", expected: "tell them") == 1)
        #expect(Answer.score(heard: "sell them", expected: "tell them") == 0.5)
    }
    @Test func clozeAndHint() {
        #expect(Answer.cloze("So we'll defend our heritage.", "Heritage") == "So we'll defend our ＿＿＿＿.")
        #expect(Answer.cloze("abc", "x") == nil)
        #expect(Answer.hint("leak", shown: 2) == "le__")
    }
    @Test func partOfSpeech() {
        let s = "So we'll defend our country and our heritage."
        #expect(WordInfo.partOfSpeech("defend", in: s) == "động từ")
        #expect(WordInfo.partOfSpeech("heritage", in: s) == "danh từ")
        #expect(WordInfo.partOfSpeech("Democrat nominee", in: "x") == "cụm từ")
    }
}

@Suite struct SpacedRepetitionTests {
    @Test func leitnerBoxes() {
        var v = VocabItem(term: "leak", meaning: "rò rỉ", termLanguage: "en-US", meaningLanguage: "vi", example: "", exampleTranslation: "")
        #expect(v.isDue)
        let t0 = Date()
        v.review(correct: true, now: t0)
        #expect(v.box == 1 && !v.isDue && abs(v.due!.timeIntervalSince(t0) - 86_400) < 1)
        v.review(correct: false, now: t0)
        #expect(v.box == 0 && v.isDue && v.reviews == 2 && v.correctCount == 1)
        for _ in 0..<5 { v.review(correct: true, now: t0) }
        #expect(v.mastered && v.box == 5)
        #expect(!v.isDue && abs(v.due!.timeIntervalSince(t0) - 30 * 86_400) < 1)
        v.review(correct: true, now: t0)
        #expect(v.box == 6 && abs(v.due!.timeIntervalSince(t0) - 60 * 86_400) < 1)
        v.review(correct: false, now: t0)
        #expect(!v.mastered && v.isDue)
    }
}

@MainActor @Suite struct PronunciationStoreTests {
    @Test func tracksUnclearWordsAndClearsAfterThreeReads() {
        let p = PronunciationStore(file: TestData.file("pron.json"))
        var a = AttributedString("I love the heritage")
        if let r = a.range(of: "heritage") { a[r].transcriptionConfidence = 0.3 }
        if let r = a.range(of: "love") { a[r].transcriptionConfidence = 0.95 }
        p.record(a, language: "en_US")
        p.record(a, language: "en_US")
        #expect(p.needsWork.map(\.word) == ["heritage"])
        #expect(p.words["love"]?.unclear == 0)
        #expect(p.words["heritage"]?.examples == ["I love the heritage"])
        let streaks = [p.retry("heritage", correct: true), p.retry("heritage", correct: true), p.retry("heritage", correct: false),
                       p.retry("heritage", correct: true), p.retry("heritage", correct: true)]
        #expect(streaks == [1, 2, 0, 1, 2] && p.needsWork.map(\.word) == ["heritage"])
        _ = p.retry("heritage", correct: true)
        #expect(p.needsWork.isEmpty)
    }
}

@Suite struct LibraryContentTests {
    @Test func topicsAndCategories() {
        #expect(Library.topics.count >= 14 && Library.topics.flatMap(\.words).count >= 180)
        #expect(Library.topics.flatMap(\.words).allSatisfy { $0.example.range(of: $0.term, options: .caseInsensitive) != nil })
        #expect(Library.categories.count >= 10 && Library.categories.allSatisfy { c in
            c.subtopics.allSatisfy { s in s.topic.map { id in Library.topics.contains { $0.id == id } } ?? (s.prompt != nil) } })
    }
    @Test func grammarCurriculum() {
        #expect(Library.grammar.count >= 45)
        #expect(Library.grammar.allSatisfy { l in
            l.level != nil && l.exercises.count >= 5 && l.exercises.allSatisfy { $0.options.contains($0.answer) && $0.prompt.contains("___") } })
        #expect(Set(Library.grammar.map(\.id)).count == Library.grammar.count)
    }
    @Test func wordlistAndDailyPick() {
        #expect(Library.wordlist.count > 8_000 && !Library.wordlist.contains("john"))
        let picked = StudyStore.pick(count: 4, curated: ["agenda", "Sprint", "agenda"], wordlist: ["the", "sprint", "of", "and"],
                                     cursor: 0, have: ["the"])
        #expect(picked.0 == ["agenda", "Sprint", "of", "and"] && picked.1 == 4)
    }
}

@MainActor @Suite struct VocabStoreTests {
    nonisolated static func load(_ url: URL) -> [VocabItem] {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return (try? d.decode([VocabItem].self, from: Data(contentsOf: url))) ?? []
    }

    @Test func unreadableFileIsMovedAsideNotOverwritten() throws {
        let url = TestData.file("vocabulary.json")
        try Data("not json".utf8).write(to: url)
        let s = VocabStore(file: url)
        #expect(s.items.isEmpty)
        #expect(FileManager.default.fileExists(atPath: url.deletingPathExtension().appendingPathExtension("unreadable.json").path))
        s.add(VocabItem(term: "leak", meaning: "rò rỉ", termLanguage: "en-US", meaningLanguage: "vi", example: "", exampleTranslation: ""))
        #expect(VocabStore(file: url).items.map(\.term) == ["leak"])
    }
}

enum TestData {
    /// A fresh file path in a unique temp folder (never the user's ~/Documents/Parley).
    static func file(_ name: String) -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "parley-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: name)
    }
}

/// AC1.2: tools never write into the owner's data folder.
@Suite struct DataSafetyTests {
    let home = FileManager.default.temporaryDirectory.appending(path: "parley-home-\(UUID().uuidString)")
    var real: URL { home.appending(path: "Documents/Parley") }

    @Test func seedRefusesTheRealFolderInAnySpelling() throws {
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let link = home.appending(path: "link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let docs = home.appending(path: "Documents")
        for path in [real.path, real.path + "/", real.path + "/.", docs.path + "/x/../Parley", real.path.uppercased(),
                     real.path + "/sub", real.path.uppercased() + "/NEW", link.path, docs.path] {
            #expect(!Seed.isAllowed(URL(fileURLWithPath: path), real: real), "must refuse \(path)")
        }
    }

    @Test func seedRefusesAnEmptyParentOfTheRealFolder() throws {
        let emptyDocs = home.appending(path: "Docs2")             // real folder not created yet → parent is empty
        try FileManager.default.createDirectory(at: emptyDocs, withIntermediateDirectories: true)
        #expect(!Seed.isAllowed(emptyDocs, real: emptyDocs.appending(path: "Parley")))
    }

    @Test func seedRefusesWhatItCannotRead() throws {
        let file = home.appending(path: "plain-file")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: file)
        #expect(!Seed.isAllowed(file, real: real))                 // not a folder → refuse, never "empty"
    }

    @Test func seedFolderArgument() {
        #expect(Seed.folder(in: ["app", "--seed", "/tmp/a"])?.path == "/tmp/a")
        #expect(Seed.folder(in: ["app", "--seed"]) == nil)
        #expect(Seed.folder(in: ["app", "--seed", "--route"]) == nil)
        #expect(Seed.folder(in: ["app", "--seed", ""]) == nil)
        #expect(Seed.folder(in: ["app"]) == nil)
    }

    @Test func seedNeedsAMissingOrEmptyFolder() throws {
        let fresh = home.appending(path: "fresh")
        #expect(Seed.isAllowed(fresh, real: real))                 // missing → created
        try FileManager.default.createDirectory(at: fresh, withIntermediateDirectories: true)
        #expect(Seed.isAllowed(fresh, real: real))                 // empty
        try Data("x".utf8).write(to: fresh.appending(path: "vocabulary.json"))
        #expect(!Seed.isAllowed(fresh, real: real))                // someone's data → refuse
    }

    @Test func seedWritesSampleDataAtomically() throws {
        let dir = home.appending(path: "seed")
        try Seed.write(to: dir)
        #expect(VocabStoreTests.load(dir.appending(path: "vocabulary.json")).count == 12)
        #expect(!Model.parse(try String(contentsOf: dir.appending(path: "\(Seed.sessionStamp).md"), encoding: .utf8)).isEmpty)
        #expect(throws: Err.self) { try Seed.write(to: dir) } // now non-empty → refused
    }

    @Test func dataDirResolution() {
        let fallback = URL(fileURLWithPath: "/default")
        #expect(Model.resolveDataDir(args: ["app"], env: [:], fallback: fallback) == fallback)
        #expect(Model.resolveDataDir(args: ["app"], env: ["PARLEY_DATA_DIR": "/env"], fallback: fallback).path == "/env")
        #expect(Model.resolveDataDir(args: ["app", "--data-dir", "/arg"], env: ["PARLEY_DATA_DIR": "/env"], fallback: fallback).path == "/arg")
        #expect(Model.resolveDataDir(args: ["app", "--data-dir"], env: [:], fallback: fallback) == fallback)          // missing value
        #expect(Model.resolveDataDir(args: ["app", "--data-dir", "--route"], env: [:], fallback: fallback) == fallback) // flag, not a path
        #expect(Model.resolveDataDir(args: ["app"], env: ["PARLEY_DATA_DIR": ""], fallback: fallback) == fallback)
    }
}
