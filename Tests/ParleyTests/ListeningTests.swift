import AVFoundation
import Foundation
import Testing
@testable import Parley

/// PARLEY-3: clips from saved sessions and word-level feedback (spec S3).
@Suite struct ClipTests {
    let url = URL(fileURLWithPath: "/tmp/x/2026-11-06_09-30-12.md")
    let notes = """
        # Parley
        <!-- parley: en_US > vi -->

        **9:30:12 AM** 🔊 Good morning everyone, let's start. <!-- t=0.5 -->
        > Chào buổi sáng.

        **9:30:14 AM** 🎤 Yes I can hear you fine. <!-- t=2.0 -->
        > Vâng tôi nghe rõ.

        **9:30:16 AM** 🔊 Okay. <!-- t=4.0 -->
        > Được.

        **9:30:20 AM** 🔊 We found a memory leak yesterday. <!-- t=6.0 -->
        > Chúng tôi tìm thấy rò rỉ bộ nhớ.

        **9:30:40 AM** 🔊 This sentence has no time offset at all.
        > Không có mốc thời gian.

        **9:31:40 AM** 🔊 The last sentence of the meeting today. <!-- t=60.0 -->
        > Câu cuối.

        """

    @Test func clipsRunToTheNextLineOfTheSameRecording() {
        let clips = Clips.from(notes: url, text: notes) { _ in true }
        #expect(clips.map(\.text) == ["Good morning everyone, let's start.", "Yes I can hear you fine.",
                                       "We found a memory leak yesterday.", "The last sentence of the meeting today."])
        // system line ends at the next *system* offset (4.0), skipping the mic line at 2.0
        #expect(abs(clips[0].start - 0.35) < 1e-9 && clips[0].end == 4.0)
        #expect(clips[1].audio?.lastPathComponent == "2026-11-06_09-30-12-mic.m4a")
        #expect(clips[0].audio?.lastPathComponent == "2026-11-06_09-30-12-may.m4a")
        #expect(clips[2].end == 6.0 + Clips.maxLength)   // next system offset is 54 s later → capped at 15 s
        #expect(clips[3].end == 60.0 + Clips.maxLength)  // last line → capped
        #expect(clips[0].translation == "Chào buổi sáng." && clips[0].origin == SessionRow.title(url))
    }

    @Test func clipsNeedTheirRecording() {
        let onlySystem = Clips.from(notes: url, text: notes) { $0.lastPathComponent.hasSuffix("-may.m4a") }
        #expect(!onlySystem.contains { $0.text.hasPrefix("Yes") } && onlySystem.count == 3)
        #expect(Clips.from(notes: url, text: notes) { _ in false }.isEmpty)
        #expect(Clips.from(notes: url, text: "") { _ in true }.isEmpty)
    }

    @Test func curatedSentencesAlwaysExist() {
        let c = Clips.curated()
        #expect(c.count >= 180 && c.allSatisfy { $0.audio == nil && !$0.text.isEmpty })
        #expect(Set(c.map(\.id)).count == c.count)
    }
}

@Suite struct WordDiffTests {
    typealias T = WordDiff.Token

    @Test func exactAnswerIgnoringCaseAndPunctuation() {
        let d = WordDiff.diff(expected: "Can we move the deadline to Friday?", typed: "can we move the deadline to friday")
        #expect(d.allSatisfy { $0.kind == .correct } && d.count == 7 && WordDiff.score(d) == 1)
        #expect(d.last?.word == "Friday?") // shows the original spelling
    }

    @Test func substitutionMissingAndExtra() {
        let d = WordDiff.diff(expected: "We need to move the deadline", typed: "we need to moved deadline please")
        #expect(d == [T(word: "We", kind: .correct), T(word: "need", kind: .correct), T(word: "to", kind: .correct),
                      T(word: "move", kind: .wrong("moved")), T(word: "the", kind: .missing),
                      T(word: "deadline", kind: .correct), T(word: "please", kind: .extra)])
        #expect(WordDiff.score(d) == 4.0 / 6.0) // extra words don't count against the expected total
    }

    @Test func emptyAnswerMissesEverything() {
        let d = WordDiff.diff(expected: "memory leak", typed: "")
        #expect(d == [T(word: "memory", kind: .missing), T(word: "leak", kind: .missing)] && WordDiff.score(d) == 0)
        #expect(WordDiff.score(WordDiff.diff(expected: "", typed: "hello")) == 0)
    }

    @Test func passThreshold() {
        // 4 of 5 words = 80 % → pass (boundary)
        let d = WordDiff.diff(expected: "one two three four five", typed: "one two three four")
        #expect(WordDiff.score(d) == 0.8 && WordDiff.score(d) >= WordDiff.pass)
        let e = WordDiff.diff(expected: "one two three four five", typed: "one two three")
        #expect(WordDiff.score(e) < WordDiff.pass)
    }

    @Test func repeatedWordsAlignInOrder() {
        let d = WordDiff.diff(expected: "the cat and the dog", typed: "the dog")
        #expect(d.filter { $0.kind == .correct }.map(\.word) == ["the", "dog"])
        #expect(d.count { $0.kind == .missing } == 3)
    }
}

/// End to end on real files: the seed records the session with `say`; every line becomes a playable clip.
@Suite struct SeededClipTests {
    @Test func seededSessionGivesFivePlayableClips() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "parley-clips-\(UUID().uuidString)")
        try Seed.write(to: dir)
        let notes = dir.appending(path: "\(Seed.sessionStamp).md")
        let clips = Clips.from(notes: notes, text: try String(contentsOf: notes, encoding: .utf8))
        #expect(clips.count == 5)
        let file = try AVAudioFile(forReading: try #require(clips.first?.audio))
        let seconds = Double(file.length) / file.processingFormat.sampleRate
        #expect(clips.allSatisfy { $0.start < $0.end && $0.end <= seconds + Clips.maxLength })
        #expect(zip(clips, clips.dropFirst()).allSatisfy { $0.end <= $1.start + 0.2 }) // clips don't overlap the next sentence
    }
}
