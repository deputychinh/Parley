import AVFoundation
import Speech

/// On-device speech-to-text in any SpeechTranscriber locale (SpeechAnalyzer). Volatile results give word-by-word latency.
final class Transcriber: @unchecked Sendable {
    let module: SpeechTranscriber
    private let analyzer: SpeechAnalyzer
    private let format: AVAudioFormat
    private let input: AsyncStream<AnalyzerInput>.Continuation
    private var converter: AVAudioConverter? // only touched from the single audio queue
    private let recordURL: URL?
    private var recorder: AVAudioFile?

    private init(module: SpeechTranscriber, analyzer: SpeechAnalyzer, format: AVAudioFormat,
                 input: AsyncStream<AnalyzerInput>.Continuation, recordURL: URL?) {
        self.module = module; self.analyzer = analyzer; self.format = format; self.input = input; self.recordURL = recordURL
    }

    /// `recordTo`: also save the raw audio as AAC (.m4a).
    /// `confidence`: tag each word with the recognizer's confidence (used to spot words the user pronounced unclearly).
    static func start(locale wanted: Locale = Locale(identifier: "en_US"), recordTo recordURL: URL? = nil,
                      confidence: Bool = false) async throws -> Transcriber {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: wanted) else {
            throw Err("Máy không hỗ trợ nhận giọng nói offline cho ngôn ngữ này")
        }
        let module = SpeechTranscriber(locale: locale, transcriptionOptions: [],
                                       reportingOptions: [.volatileResults, .fastResults],
                                       attributeOptions: confidence ? [.transcriptionConfidence] : [])
        // Downloads the on-device model for this language once; no-op afterwards.
        if let req = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await req.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            throw Err("Không có định dạng audio phù hợp cho bộ nhận giọng nói")
        }
        let analyzer = SpeechAnalyzer(modules: [module])
        let (stream, input) = AsyncStream<AnalyzerInput>.makeStream()
        try await analyzer.start(inputSequence: stream)
        return Transcriber(module: module, analyzer: analyzer, format: format, input: input, recordURL: recordURL)
    }

    func feed(_ buf: AVAudioPCMBuffer) {
        if let recordURL, recorder == nil {
            recorder = try? AVAudioFile(forWriting: recordURL,
                                        settings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
                                                   AVSampleRateKey: buf.format.sampleRate,
                                                   AVNumberOfChannelsKey: buf.format.channelCount],
                                        commonFormat: buf.format.commonFormat, interleaved: buf.format.isInterleaved)
        }
        try? recorder?.write(from: buf)
        if converter?.inputFormat != buf.format { converter = AVAudioConverter(from: buf.format, to: format) }
        guard let converter else { return }
        let cap = AVAudioFrameCount(Double(buf.frameLength) * format.sampleRate / buf.format.sampleRate) + 1
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: cap) else { return }
        var given = false
        converter.convert(to: out, error: nil) { _, status in
            if given { status.pointee = .noDataNow; return nil }
            given = true
            status.pointee = .haveData
            return buf
        }
        if out.frameLength > 0 { input.yield(AnalyzerInput(buffer: out)) }
    }

    /// Flushes pending audio so the last sentence is finalized, then ends `module.results`.
    func finish() async throws {
        input.finish()
        recorder?.close()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
    }
}
