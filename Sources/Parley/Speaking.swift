import AVFoundation
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

    mutating func feed(level: Float, at t: Double) -> Stop? {
        let base = min(floor ?? level, level)
        floor = base
        let speech = level > Self.loud || level > max(base + Self.margin, Self.minSpeech)
        run = speech ? run + 1 : 0
        if run >= 2 || (speech && heardSpeech) { heardSpeech = true; lastSpeech = t } // one frame alone: a click
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
    var busy: Bool { starting || stopping }

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
    private(set) var recording: URL?
    var playingMine = false
    @ObservationIgnored private var failure: String?
    @ObservationIgnored private var finishRequested = false
    @ObservationIgnored private let meter = LevelMeter()
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var transcriber: Transcriber?
    @ObservationIgnored private var collector: Task<String, Never>?

    /// What to tell the learner after a stop: the recognizer's own error wins over "nothing heard".
    nonisolated static func emptyResultMessage(heard: String, error: String?) -> String? {
        guard heard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return error ?? "Chưa nghe thấy gì — kiểm tra micro (System Settings → Privacy & Security → Microphone) rồi thử lại."
    }

    /// One press: listens until the speaker stops (`quiet` s of silence after speech), nothing is heard for 6 s, `cap`
    /// is reached, or `finish()` (a second press). Returns what was recognized ("" when nothing).
    func listen(language: String, cap: Double, quiet: Double = EndPointer.defaultQuiet) async -> String {
        guard !listening, !busy else { return "" }
        stopMine()
        Self.discard(recording)
        recording = nil
        let url = Self.attemptURL()
        await start(language: language, recordTo: url)
        guard listening else { return "" }
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
        if reason == .noSpeech, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { error = Self.noSpeech }
        return text
    }

    /// A second press while listening: end now and score what was said.
    func finish() { finishRequested = true }

    nonisolated static let noSpeech = "Không nghe thấy tiếng — kiểm tra micro rồi thử lại."
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

    func start(language: String, recordTo: URL? = nil) async {
        guard !listening, !busy else { return }
        starting = true
        defer { starting = false }
        heard = nil
        error = nil
        var started: Transcriber?
        do {
            let t = try await Transcriber.start(locale: Locale(identifier: language), recordTo: recordTo)
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
    func body(content: Content) -> some View {
        content.background {
            Circle()
                .fill(Color.parley.opacity(0.25))
                .scaleEffect(mic.listening ? 1 + 0.6 * mic.level : 1)
                .opacity(mic.listening ? 1 : 0)
                .animation(.easeOut(duration: 0.12), value: mic.level)
                .accessibilityHidden(true)
        }
    }
}

extension View {
    func micLevel(_ mic: MicCheck) -> some View { modifier(MicLevel(mic: mic)) }
}

/// "Nghe lại giọng tôi" (⌥M): the learner's last attempt, to compare with "Nghe mẫu".
struct MyVoiceButton: View {
    let mic: MicCheck
    var body: some View {
        if mic.recording != nil, !mic.listening {
            Button { mic.playingMine ? mic.stopMine() : mic.playMine() } label: {
                Label(mic.playingMine ? "Dừng" : "Nghe lại giọng tôi", systemImage: mic.playingMine ? "stop.fill" : "person.wave.2")
            }
            .buttonStyle(.glass)
            .keyboardShortcut("m", modifiers: .option)
            .help("Nghe lại giọng bạn vừa nói (⌥M), so với giọng mẫu")
        }
    }
}
