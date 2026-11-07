import Foundation
import Testing
@testable import Parley

/// Data safety for every store (review findings on PARLEY-2): unique aside names, read-only when the move fails,
/// save errors reported instead of swallowed.
@MainActor @Suite struct StoreFileTests {
    @Test func secondCorruptFileGetsItsOwnAsideName() throws {
        let url = TestData.file("activity.json")
        try Data("{ first".utf8).write(to: url)
        _ = ActivityStore(file: url)
        try Data("{ second".utf8).write(to: url)
        let s = ActivityStore(file: url)
        s.add(.grammar, xp: 10)
        let aside = TestData.asideFiles(of: url)
        #expect(aside.count == 2)
        let contents = Set(try aside.map { try String(contentsOf: $0, encoding: .utf8) })
        #expect(contents == ["{ first", "{ second"]) // both damaged files kept
        #expect(s.problem?.contains("cất sang") == true)
    }

    @Test func storeIsReadOnlyWhenTheBadFileCannotBeMoved() throws {
        let url = TestData.file("vocabulary.json")
        let dir = url.deletingLastPathComponent()
        try Data("{ broken".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path) // no rename in this folder
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }
        let s = VocabStore(file: url)
        s.add(VocabItem(term: "x", meaning: "", termLanguage: "en-US", meaningLanguage: "vi", example: "", exampleTranslation: ""))
        #expect(try String(contentsOf: url, encoding: .utf8) == "{ broken") // never overwritten
        #expect(s.problem?.contains("không ghi đè") == true)
    }

    @Test func saveErrorsAreReported() throws {
        let url = TestData.file("activity.json")
        let s = ActivityStore(file: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) // a folder where the file should go
        s.add(.grammar, xp: 10)
        #expect(s.problem?.hasPrefix("Không lưu được") == true)
    }

    @Test func missingFileIsAFirstLaunch() {
        let loaded = StoreFile.load([String].self, from: TestData.file("none.json"))
        #expect(loaded.value == nil && loaded.writable && loaded.problem == nil)
    }

    @Test func asideNamesAreUnique() {
        let url = URL(fileURLWithPath: "/tmp/a/study.json")
        let now = Date()
        let a = StoreFile.asideURL(for: url, now: now), b = StoreFile.asideURL(for: url, now: now)
        #expect(a != b && a.lastPathComponent.hasPrefix("study.unreadable-") && a.pathExtension == "json")
    }
}

/// AC2.1: every graded answer logs XP for the right skill — through the stores, so a missing call fails here.
@MainActor @Suite struct XPWiringTests {
    func fresh() -> ActivityStore { ActivityStore(file: TestData.file("activity.json")) }
    var today: String { StudyStore.day(.now) }

    @Test(arguments: [
        (XPEvent.review(ok: true, spoken: false), Skill.vocabulary, 10),
        (.review(ok: false, spoken: false), .vocabulary, 2),
        (.review(ok: true, spoken: true), .speaking, 10),
        (.grammar(ok: true), .grammar, 10),
        (.grammar(ok: false), .grammar, 2),
        (.pronunciation(ok: true), .speaking, 10),
        (.newWord, .vocabulary, 5),
        (.listening(dictation: true, pass: true), .listening, 10),
        (.listening(dictation: false, pass: false), .speaking, 2),
        (.turn(spoken: true), .speaking, 15),
        (.turn(spoken: false), .writing, 15),
    ])
    func eventRules(event: XPEvent, skill: Skill, xp: Int) {
        #expect(event.skill == skill && event.xp == xp)
    }

    @Test func vocabularyReviewLogsXP() {
        let a = fresh()
        let v = VocabStore(file: TestData.file("vocabulary.json"), activity: a)
        v.add(VocabItem(term: "leak", meaning: "rò rỉ", termLanguage: "en-US", meaningLanguage: "vi", example: "", exampleTranslation: ""))
        v.review(v.items[0].id, correct: true)
        v.review(v.items[0].id, correct: false, spoken: true)
        #expect(a.data.days[today] == ["vocabulary": 10, "speaking": 2])
    }

    @Test func grammarAndNewWordsLogXP() {
        let a = fresh()
        let s = StudyStore(file: TestData.file("study.json"), activity: a)
        s.answerGrammar(correct: true)
        s.answerGrammar(correct: false)
        s.resolve("agenda", learned: true, vocab: VocabStore(file: TestData.file("v.json")))
        s.resolve("the", learned: false, vocab: VocabStore(file: TestData.file("v.json"))) // "Đã biết" earns nothing
        s.resolve("agenda", learned: true, vocab: VocabStore(file: TestData.file("v.json"))) // already done → no double XP
        #expect(a.data.days[today] == ["grammar": 12, "vocabulary": 5])
    }

    @Test func pronunciationRetryLogsXP() {
        let a = fresh()
        let p = PronunciationStore(file: TestData.file("pron.json"), activity: a)
        var text = AttributedString("heritage")
        text.transcriptionConfidence = 0.2
        p.record(text, language: "en_US")
        _ = p.retry("heritage", correct: true)
        _ = p.retry("unknown-word", correct: true) // not in the list → nothing
        #expect(a.data.days[today] == ["speaking": 10])
    }

    @Test func metSurvivesARestart() {
        let url = TestData.file("activity.json")
        let a = ActivityStore(file: url)
        a.goal = 20
        a.add(.grammar, xp: 20)
        let reloaded = ActivityStore(file: url)
        #expect(reloaded.data.met == [today] && reloaded.streak == 1 && reloaded.metToday)
    }
}

/// PARLEY-13: sandboxed runs (screenshots, reviews) never use the owner's settings or reminders.
@Suite struct SandboxDefaultsTests {
    @Test func sandboxIsDetectedFromFlagOrEnvironment() {
        #expect(AppDefaults.isSandbox(args: ["app", "--data-dir", "/tmp/x"], env: [:]))
        #expect(AppDefaults.isSandbox(args: ["app"], env: ["PARLEY_DATA_DIR": "/tmp/x"]))
        #expect(AppDefaults.isSandbox(args: ["app", "--data-dir"], env: [:]))      // malformed still counts as sandbox
        #expect(!AppDefaults.isSandbox(args: ["app"], env: [:]))
        #expect(!AppDefaults.isSandbox(args: ["app"], env: ["PARLEY_DATA_DIR": ""]))
    }

    @Test func testsRunSandboxedWithTheirOwnDefaults() {
        // `make test` sets PARLEY_DATA_DIR, so this process must not see the owner's defaults domain.
        #expect(AppDefaults.sandboxed && AppDefaults.store !== UserDefaults.standard)
        #expect(AppDefaults.sandboxSuite.hasPrefix("parley.sandbox.") && AppDefaults.sandboxSuite.hasSuffix("\(ProcessInfo.processInfo.processIdentifier)"))
    }

    /// The reminder guard: in a sandboxed process nothing reaches UNUserNotificationCenter (it would also crash
    /// outside an app bundle, so removing a guard fails this test).
    @MainActor @Test func sandboxedRunsNeverTouchNotifications() async {
        Reminder.reschedule(activity: nil)
        #expect(await Reminder.isDenied() == false)
        #expect(await Reminder.requestPermission() == false)
        try? await Task.sleep(for: .milliseconds(200))
    }
}


@Suite struct SandboxCleanupTests {
    @Test func staleDomainsAreFoundButNotOurOwn() {
        let names = ["parley.sandbox.111.plist", "parley.sandbox.plist", "parley.sandbox.222.plist", "com.david.parley.plist", "other.plist"]
        // 111 has exited, 333 is still running (another screenshot), 222 is us
        let names2 = names + ["parley.sandbox.333.plist"]
        #expect(AppDefaults.staleSandboxDomains(fileNames: names2, own: "parley.sandbox.222", isAlive: { $0 == 333 })
                == ["parley.sandbox.111", "parley.sandbox"])
    }

    @Test func removeDomainDeletesTheFile() throws {
        let prefs = FileManager.default.temporaryDirectory.appending(path: "parley-prefs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: prefs, withIntermediateDirectories: true)
        let file = prefs.appending(path: "parley.sandbox.999999.plist")
        try Data("x".utf8).write(to: file)
        AppDefaults.removeDomain("parley.sandbox.999999", prefs: prefs)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func theRealAppRefusesToRunSandboxed() {
        #expect(AppDefaults.refusesSandboxedRun(bundleID: "com.david.parley", sandboxed: true))
        #expect(!AppDefaults.refusesSandboxedRun(bundleID: "com.david.parley.sandbox", sandboxed: true))
        #expect(!AppDefaults.refusesSandboxedRun(bundleID: "com.david.parley", sandboxed: false))
        #expect(!AppDefaults.refusesSandboxedRun(bundleID: nil, sandboxed: true)) // CLI binary (tests, --seed)
        #expect(AppDefaults.processIsAlive(getpid()) && !AppDefaults.processIsAlive(999_999))
    }
}
