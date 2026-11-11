import AVFoundation
import AppKit
import Accelerate
import SwiftUI
import os

/// When a speaking attempt ends by itself (PARLEY-31): speech, then `quiet` seconds below the speech threshold
/// (`.silence`); nothing heard within `noSpeech` seconds; or the `cap`. Levels are RMS in dBFS, one per ~100 ms.
struct EndPointer: Equatable {
    enum Stop: Equatable { case silence, noSpeech, cap }
    nonisolated static let defaultQuiet = 1.2
    /// Speech is louder than the quietest level so far (room noise) by `margin` dB and above `minSpeech`, or above
    /// `loud` outright (speaking from the very first frame never lowers the floor below the voice).
    nonisolated static let margin: Float = 12, minSpeech: Float = -50, loud: Float = -30

    var quiet = defaultQuiet
    var noSpeech = 6.0
    var cap: Double
    private(set) var floor: Float?
    private(set) var run = 0          // frames in a row above the threshold
    private(set) var heardSpeech = false
    private(set) var lastSpeech = 0.0

    init(quiet: Double = defaultQuiet, noSpeech: Double = 6, cap: Double) {
        self.quiet = quiet; self.noSpeech = noSpeech; self.cap = cap
    }

    /// Below this a frame is a dropout (no buffer yet, the engine starting), not a quiet room.
    nonisolated static let dropout: Float = -150
    /// The floor follows a louder room slowly (dB per frame), so one quiet moment does not lower the bar for good.
    nonisolated static let floorRise: Float = 0.3

    mutating func feed(level: Float, at t: Double) -> Stop? {
        guard level > Self.dropout else { return timeRule(at: t) } // no audio this frame: only the clock counts
        let base = min(floor ?? level, level)
        let speech = level > Self.loud || level > max(base + Self.margin, Self.minSpeech)
        // The floor follows a louder room only on frames that are not speech: a long, quiet sentence is never cut.
        floor = speech ? base : min(base + Self.floorRise, level)
        run = speech ? run + 1 : 0
        if run >= 2 || (speech && heardSpeech) { heardSpeech = true; lastSpeech = t } // one frame alone: a click
        return timeRule(at: t)
    }

    private func timeRule(at t: Double) -> Stop? {
        if t >= cap { return .cap }
        guard heardSpeech else { return t >= noSpeech ? .noSpeech : nil }
        return t - lastSpeech >= quiet ? .silence : nil
    }
}

/// Peak RMS level of the mic buffers since the last `take()`; written on the audio thread, read on the main actor.
final class LevelMeter: Sendable {
    private let peak = OSAllocatedUnfairLock<Float>(initialState: -160)

    func record(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData, buffer.frameLength > 0 else { return }
        let db = Self.db(UnsafeBufferPointer(start: data[0], count: Int(buffer.frameLength)))
        peak.withLock { $0 = max($0, db) }
    }

    func take() -> Float { peak.withLock { p in defer { p = -160 }; return p } }

    /// RMS of the samples in dBFS (−160 for silence).
    nonisolated static func db(_ samples: UnsafeBufferPointer<Float>) -> Float {
        guard let base = samples.baseAddress, !samples.isEmpty else { return -160 }
        var rms: Float = 0
        vDSP_rmsqv(base, 1, &rms, vDSP_Length(samples.count))
        return rms > 0 ? max(-160, 20 * log10(rms)) : -160
    }

    /// −60…−10 dBFS → 0…1 for the level ring.
    nonisolated static func display(_ db: Float) -> Double { Double(min(1, max(0, (db + 60) / 50))) }
}

/// Records the microphone and runs it through on-device speech recognition (pronunciation check).
@Observable @MainActor
final class MicCheck {
    var listening = false
    var starting = false   // while the recognizer and audio engine come up: a second tap does nothing
    var stopping = false   // between "stop" and the recognizer's last result: buttons wait
    var busy: Bool { starting || stopping || pending }
    /// From the press until the recognizer runs (the permission prompt included): a second press does nothing.
    var pending = false

    enum StopAction: Equatable { case ignore, lastResult, stop }
    /// What `stop()` does: nothing while starting or already stopping (never an older result), the last result when
    /// not listening, otherwise a real stop.
    nonisolated static func stopAction(listening: Bool, starting: Bool, stopping: Bool) -> StopAction {
        if starting || stopping { return .ignore }
        return listening ? .stop : .lastResult
    }
    var heard: String?
    var error: String?
    /// 0…1 for the level ring while listening.
    var level: Double = 0
    /// The last attempt's audio ("Nghe lại giọng tôi"); deleted when the next attempt starts and at launch / quit.
    var recording: URL?
    var playingMine = false
    @ObservationIgnored private var failure: String?
    @ObservationIgnored private var finishRequested = false
    /// Bumped by `reset()`; `listen` reports only if it is still the current attempt.
    @ObservationIgnored private(set) var attempt = 0
    @ObservationIgnored private let meter = LevelMeter()
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var transcriber: Transcriber?
    @ObservationIgnored private var collector: Task<String, Never>?

    /// What to tell the learner after a stop: the recognizer's own error wins over "nothing heard".
    nonisolated static func emptyResultMessage(heard: String, error: String?) -> String? {
        guard heard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return error ?? noSpeech
    }

    /// One press: listens until the speaker stops (`quiet` s of silence after speech), nothing is heard for 6 s, `cap`
    /// is reached, or `finish()` (a second press). Returns what was recognized ("" when nothing).
    func listen(language: String, cap: Double, quiet: Double = EndPointer.defaultQuiet, context: [String] = []) async -> String {
        guard !listening, !busy else { return "" }
        reset()
        Speaker.stop() // the model voice must never be recorded and scored
        pending = true
        let mine = attempt
        var allowed = Self.permission(AVCaptureDevice.authorizationStatus(for: .audio))
        if allowed == .ask { allowed = await AVCaptureDevice.requestAccess(for: .audio) ? .go : .refuse }
        let gate = Self.gate(allowed)
        permissionDenied = gate.denied
        guard gate.go, mine == attempt else {
            pending = false
            if mine == attempt { error = gate.error }
            return ""
        }
        let url = Self.attemptURL()
        await start(language: language, recordTo: url, context: context)
        pending = false
        guard listening, mine == attempt else { Self.discard(url); return "" }
        recording = url
        finishRequested = false
        var end = EndPointer(quiet: quiet, cap: cap)
        let began = ContinuousClock.now
        var reason: EndPointer.Stop?
        _ = meter.take()
        while listening, !finishRequested, reason == nil, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(100))
            let db = meter.take()
            level = LevelMeter.display(db)
            let elapsed = began.duration(to: .now)
            reason = end.feed(level: db, at: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18)
        }
        level = 0
        let text = await stop()
        let plan = Self.finish(text: text, error: error, current: mine == attempt)
        guard plan.report else { return "" } // skipped or reset meanwhile: say nothing about the next item
        if plan.discardRecording { Self.discard(recording); recording = nil }
        error = plan.error
        return text
    }

    /// What `listen` does once the mic stopped. `current` = no reset / skip happened during the attempt.
    struct Finish: Equatable {
        var report: Bool            // false: the attempt was abandoned; touch nothing, return ""
        var discardRecording: Bool  // nothing recognized: keep no silent recording
        var error: String?
    }

    nonisolated static func finish(text: String, error: String?, current: Bool) -> Finish {
        guard current else { return Finish(report: false, discardRecording: false, error: nil) }
        let end = ended(text: text, error: error)
        return Finish(report: true, discardRecording: !end.keep, error: end.error)
    }

    /// Permission → may we listen, is "Mở Cài đặt" needed, what to say.
    nonisolated static func gate(_ p: Permission) -> (go: Bool, denied: Bool, error: String?) {
        p == .go ? (true, false, nil) : (false, true, denied)
    }

    /// After an attempt: nothing recognized → keep no (silent) recording and say why; a recognizer error wins.
    nonisolated static func ended(text: String, error: String?) -> (keep: Bool, error: String?) {
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return (true, error) }
        return (false, error ?? noSpeech)
    }

    /// A second press while listening: end now and score what was said.
    func finish() { finishRequested = true }

    nonisolated static let noSpeech = "Không nghe thấy tiếng — kiểm tra micro rồi thử lại."
    nonisolated static let denied = "Parley chưa được dùng micro. Bật Parley trong Cài đặt hệ thống → Quyền riêng tư & Bảo mật → Micro."

    /// Microphone permission was refused: the learner needs "Mở Cài đặt", not "try again".
    private(set) var permissionDenied = false

    /// What to do before listening: ask once, go on when allowed, stop with `denied` otherwise.
    enum Permission: Equatable { case ask, go, refuse }
    nonisolated static func permission(_ status: AVAuthorizationStatus) -> Permission {
        switch status {
        case .authorized: .go
        case .notDetermined: .ask
        default: .refuse
        }
    }

    /// A new card or word: forget the last attempt (its replay, text and message) and stop any playback.
    func reset() {
        attempt += 1 // an attempt still finishing belongs to the previous card: it must not report
        stopMine()
        Self.discard(recording)
        recording = nil
        heard = nil
        error = nil
    }

    func openMicSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
    }
    /// Caps (seconds) for one word and for a conversation turn.
    nonisolated static let wordCap = 5.0, turnCap = 30.0, turnQuiet = 2.0

    /// "Nghe lại giọng tôi".
    func playMine() {
        guard let recording, let p = try? AVAudioPlayer(contentsOf: recording) else { return }
        Speaker.stop()
        player = p
        p.play()
        playingMine = true
        Task {
            try? await Task.sleep(for: .seconds(p.duration + 0.1))
            if player === p { playingMine = false }
        }
    }

    func stopMine() {
        player?.stop()
        player = nil
        playingMine = false
    }

    /// Learner attempts live here only: `tmp/parley-attempts/`.
    nonisolated static var attemptsFolder: URL { FileManager.default.temporaryDirectory.appending(path: "parley-attempts") }
    nonisolated static func attemptURL(in folder: URL = attemptsFolder) -> URL {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "\(UUID().uuidString).m4a")
    }
    nonisolated static func discard(_ url: URL?) { if let url { try? FileManager.default.removeItem(at: url) } }
    /// At launch and quit: no attempt outlives the app.
    nonisolated static func clearAttempts(in folder: URL = attemptsFolder) { try? FileManager.default.removeItem(at: folder) }

    func start(language: String, recordTo: URL? = nil, context: [String] = []) async {
        guard !listening, !starting, !stopping else { return } // `pending` is listen() itself: go on
        starting = true
        defer { starting = false }
        heard = nil
        error = nil
        var started: Transcriber?
        do {
            let t = try await Transcriber.start(locale: Locale(identifier: language), recordTo: recordTo, context: context)
            started = t
            collector = Task {
                var out: [String] = []
                do {
                    for try await r in t.module.results where r.isFinal { out.append(String(r.text.characters)) }
                } catch {
                    await MainActor.run { self.failure = "Nhận dạng giọng nói bị lỗi — thử nói lại." }
                    print("mic:", error)
                }
                return out.joined(separator: " ")
            }
            let engine = AVAudioEngine()
            let input = engine.inputNode
            input.installTap(onBus: 0, bufferSize: 4096, format: input.outputFormat(forBus: 0), block: Self.tap(t, meter))
            try engine.start()
            self.engine = engine
            transcriber = t
            listening = true
        } catch {
            // clean up what was started so nothing keeps running or leaks
            collector?.cancel()
            collector = nil
            if let started { try? await started.finish() }
            self.error = "Không mở được micro: \(error.localizedDescription)"
        }
    }

    func stop() async -> String {
        switch Self.stopAction(listening: listening, starting: starting, stopping: stopping) {
        case .ignore: return ""
        case .lastResult: return heard ?? ""
        case .stop: break
        }
        stopping = true
        defer { stopping = false }
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        listening = false
        do { try await transcriber?.finish() } catch {
            print("mic finish:", error)
            failure = failure ?? "Nhận dạng giọng nói bị lỗi — thử nói lại."
        }
        transcriber = nil
        let text = await collector?.value ?? ""
        collector = nil
        heard = text
        if let failure { error = failure; self.failure = nil }
        return text
    }

    /// Built outside the main actor: the tap runs on an audio thread.
    private nonisolated static func tap(_ t: Transcriber, _ meter: LevelMeter) -> AVAudioNodeTapBlock {
        { buffer, _ in
            meter.record(buffer)
            t.feed(buffer)
        }
    }
}

/// The level ring around a mic button: it grows with the voice, so the learner sees Parley hears them.
struct MicLevel: ViewModifier {
    let mic: MicCheck
    var active = true   // a list with one mic per row: only the row that is listening
    func body(content: Content) -> some View {
        let on = mic.listening && active
        content.background {
            Capsule()
                .fill(Color.parley.opacity(0.25))
                .scaleEffect(on ? 1 + 0.6 * mic.level : 1)
                .opacity(on ? 1 : 0)
                .animation(.easeOut(duration: 0.12), value: mic.level)
                .accessibilityHidden(true)
        }
    }
}

extension View {
    func micLevel(_ mic: MicCheck, active: Bool = true) -> some View { modifier(MicLevel(mic: mic, active: active)) }
}

/// "Nghe lại giọng tôi" (⌥M): the learner's last attempt, to compare with "Nghe mẫu".
struct MyVoiceButton: View {
    let mic: MicCheck
    var body: some View {
        if mic.permissionDenied {
            Button { mic.openMicSettings() } label: { Label("Mở Cài đặt", systemImage: "gear") }
                .buttonStyle(.glass)
                .help("Cho phép Parley dùng micro")
        } else if mic.recording != nil, !mic.listening {
            Button { mic.playingMine ? mic.stopMine() : mic.playMine() } label: {
                Label(mic.playingMine ? "Dừng" : "Nghe lại giọng tôi", systemImage: mic.playingMine ? "stop.fill" : "person.wave.2")
            }
            .buttonStyle(.glass)
            .keyboardShortcut("m", modifiers: .option)
            .help("Nghe lại giọng bạn vừa nói (⌥M), so với giọng mẫu")
        }
    }
}
