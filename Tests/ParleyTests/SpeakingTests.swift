import Foundation
import Testing
@testable import Parley

/// PARLEY-31: the one-press mic ends by itself when the learner stops talking.
@MainActor
struct EndPointerTests {
    /// Feeds one level per 100 ms; returns the stop and when it came.
    private func run(_ levels: [Float], quiet: Double = 1.2, cap: Double = 30) -> (EndPointer.Stop?, Double) {
        var end = EndPointer(quiet: quiet, cap: cap)
        for (i, level) in levels.enumerated() {
            let t = Double(i + 1) * 0.1
            if let stop = end.feed(level: level, at: t) { return (stop, t) }
        }
        return (nil, Double(levels.count) * 0.1)
    }

    @Test func stopsAfterQuietOnceSpeechWasHeard() {
        let levels = [Float](repeating: -60, count: 5) + [Float](repeating: -25, count: 10) + [Float](repeating: -58, count: 20)
        let (stop, t) = run(levels)
        #expect(stop == .silence)
        #expect(abs(t - 2.7) < 0.01) // last speech at 1.5 s + 1.2 s quiet
    }

    @Test func pausesShorterThanQuietDoNotStop() {
        let speech = [Float](repeating: -25, count: 5), pause = [Float](repeating: -60, count: 10) // 1.0 s < 1.2 s
        let (stop, _) = run(speech + pause + speech + pause + speech)
        #expect(stop == nil)
        #expect(run(speech + pause + speech, quiet: 2).0 == nil) // conversation: 2 s
    }

    @Test func nothingHeardStopsAtSixSeconds() {
        let (stop, t) = run([Float](repeating: -62, count: 80))
        #expect(stop == .noSpeech && abs(t - 6) < 0.01)
    }

    @Test func oneClickIsNotSpeech() {
        var levels = [Float](repeating: -62, count: 80)
        levels[3] = -20 // a single loud frame (a click, a key)
        #expect(run(levels).0 == .noSpeech)
    }

    @Test func speakingFromTheFirstFrameCounts() {
        // The floor starts at the voice itself; loud frames count anyway.
        let (stop, t) = run([Float](repeating: -22, count: 8) + [Float](repeating: -55, count: 20))
        #expect(stop == .silence && abs(t - 2.0) < 0.01)
    }

    @Test func quietVoiceInAQuietRoomCounts() {
        // −45 dBFS is under the "loud" mark but 12 dB above a −65 room.
        let (stop, _) = run([Float](repeating: -65, count: 5) + [Float](repeating: -45, count: 6) + [Float](repeating: -65, count: 14))
        #expect(stop == .silence)
    }

    @Test func capEndsALongTurn() {
        let (stop, t) = run([Float](repeating: -25, count: 60), cap: 5)
        #expect(stop == .cap && abs(t - 5) < 0.01)
    }

    @Test func defaultsArePinned() {
        // The owner's "nói xong là tự dừng": 1.2 s of quiet, 6 s with nothing, 12 dB over the room.
        #expect(EndPointer.defaultQuiet == 1.2 && EndPointer.margin == 12 && EndPointer.minSpeech == -50 && EndPointer.loud == -30)
        var end = EndPointer(cap: 30)
        #expect(end.quiet == 1.2 && end.noSpeech == 6)
        var t = 0.0
        for level: Float in [-60, -60, -25, -25, -25] { t += 0.1; #expect(end.feed(level: level, at: t) == nil) }
        var stop: EndPointer.Stop?
        while stop == nil, t < 10 { t += 0.1; stop = end.feed(level: -60, at: t) }
        #expect(stop == .silence && abs(t - 1.7) < 0.01)
        #expect(MicCheck.wordCap == 5 && MicCheck.turnCap == 30 && MicCheck.turnQuiet == 2)
    }

    @Test func aDropoutDoesNotTurnARoomIntoSpeech() {
        // Engine start: empty frames (−160) must not become the floor, or a −45 room counts as speech until the cap.
        let levels = [Float](repeating: -160, count: 3) + [Float](repeating: -45, count: 70)
        #expect(run(levels, cap: 30).0 == .noSpeech)
        // The floor rises only between words: a room that gets a little louder is followed…
        var end = EndPointer(cap: 60)
        var t = 0.0
        for _ in 0..<10 { t += 0.1; _ = end.feed(level: -70, at: t) }
        for _ in 0..<5 { t += 0.1; _ = end.feed(level: -61, at: t) } // 9 dB up: not speech, the floor climbs
        #expect((end.floor ?? -99) > -70)
        // …while a steady loud sound that starts at once (a fan) counts as a voice and only the cap ends it —
        // the trade for never cutting a long, quiet sentence (aLongQuietSentenceIsNotCut).
        var stop: EndPointer.Stop?
        for _ in 0..<700 where stop == nil { t += 0.1; stop = end.feed(level: -45, at: t) }
        #expect(stop == .cap)
    }

    @Test func micPermission() {
        #expect(MicCheck.permission(.authorized) == .go)
        #expect(MicCheck.permission(.notDetermined) == .ask)
        #expect(MicCheck.permission(.denied) == .refuse && MicCheck.permission(.restricted) == .refuse)
        #expect(MicCheck.denied.contains("Micro"))
        #expect(MicCheck.emptyResultMessage(heard: " ", error: nil) == MicCheck.noSpeech)
        #expect(MicCheck.emptyResultMessage(heard: "ship", error: nil) == nil)
        #expect(MicCheck.emptyResultMessage(heard: "", error: "lỗi") == "lỗi")
    }

    @Test func resetForgetsTheLastAttempt() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "parley-attempts-test-\(UUID().uuidString)")
        let file = MicCheck.attemptURL(in: folder)
        try Data([1, 2, 3]).write(to: file)
        let mic = MicCheck()
        mic.recording = file
        mic.heard = "ship"
        mic.error = "x"
        mic.reset()
        #expect(mic.heard == nil && mic.error == nil && mic.recording == nil && !mic.playingMine)
        #expect(!FileManager.default.fileExists(atPath: file.path)) // the old attempt is gone, not just forgotten
        MicCheck.clearAttempts(in: folder)
    }

    @Test func anEmptyAttemptKeepsNoRecordingAndSaysWhy() {
        #expect(MicCheck.ended(text: " ", error: nil) == (false, MicCheck.noSpeech))
        #expect(MicCheck.ended(text: "", error: "Nhận dạng lỗi") == (false, "Nhận dạng lỗi"))
        #expect(MicCheck.ended(text: "ship", error: nil) == (true, nil))
    }

    @Test func aLongQuietSentenceIsNotCut() {
        // A steady −42 dBFS voice in a −65 room for 10 s: the floor must not climb under the voice.
        let levels = [Float](repeating: -65, count: 5) + [Float](repeating: -42, count: 100) + [Float](repeating: -65, count: 20)
        let (stop, t) = run(levels)
        #expect(stop == .silence && abs(t - 11.7) < 0.01) // last speech at 10.5 s + 1.2 s
        // 12 dB over the room is the line: 11 dB over a −70 room (and under −50) is not speech; 13 dB is.
        #expect(run([Float](repeating: -70, count: 5) + [Float](repeating: -59, count: 70)).0 == .noSpeech)
        #expect(run([Float](repeating: -62, count: 5) + [Float](repeating: -49, count: 10) + [Float](repeating: -62, count: 20)).0 == .silence)
    }

    @Test func levelsInDecibels() {
        let quiet = [Float](repeating: 0, count: 512), full = [Float](repeating: 1, count: 512)
        let tenth = (0..<4800).map { Float(0.1 * sin(Double($0) * 2 * .pi * 440 / 48_000)) }
        #expect(quiet.withUnsafeBufferPointer(LevelMeter.db) == -160)
        #expect(abs(full.withUnsafeBufferPointer(LevelMeter.db)) < 0.01)
        #expect(abs(tenth.withUnsafeBufferPointer(LevelMeter.db) - (-23.01)) < 0.1) // sine RMS = 0.1/√2
        #expect(LevelMeter.display(-60) == 0 && LevelMeter.display(-10) == 1 && LevelMeter.display(-160) == 0)
    }

    @Test func attemptsLiveInOneTempFolderAndAreCleared() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "parley-attempts-test-\(UUID().uuidString)")
        let a = MicCheck.attemptURL(in: folder), b = MicCheck.attemptURL(in: folder)
        #expect(a != b && a.deletingLastPathComponent().path == folder.path && a.pathExtension == "m4a")
        try Data([1]).write(to: a)
        try Data([2]).write(to: b)
        MicCheck.discard(a)
        #expect(!FileManager.default.fileExists(atPath: a.path) && FileManager.default.fileExists(atPath: b.path))
        MicCheck.clearAttempts(in: folder)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        #expect(MicCheck.attemptsFolder.path.hasPrefix(FileManager.default.temporaryDirectory.path))
    }
}
