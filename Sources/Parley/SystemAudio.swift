import Accelerate
import AVFoundation
import ScreenCaptureKit

enum Source: CaseIterable {
    case system, mic
    var tag: String { self == .mic ? "🎤 " : "🔊 " } // used in the markdown notes
    var fileSuffix: String { self == .mic ? "mic" : "may" }
    var label: String { self == .mic ? "Micro của bạn" : "Âm thanh máy" }
    var symbol: String { self == .mic ? "mic.fill" : "speaker.wave.2.fill" }
}

/// Captures everything the Mac plays (meeting apps, browser, video) plus, optionally, the default microphone.
final class SystemAudio: NSObject, SCStreamOutput, SCRecordingOutputDelegate {
    var onBuffer: ((AVAudioPCMBuffer, Source) -> Void)?
    var onLevel: ((Source, Float) -> Void)? // RMS, throttled to ~15 Hz per source
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "system-audio")
    private var lastLevel: [Source: UInt64] = [:]

    /// `recordScreenTo`: also save a full-resolution screen video (with system audio) to this .mov.
    func start(includeMic: Bool, recordScreenTo videoURL: URL? = nil) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { throw Err("Không tìm thấy màn hình để gắn luồng âm thanh") }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let cfg = SCStreamConfiguration()
        cfg.capturesAudio = true
        cfg.excludesCurrentProcessAudio = true
        cfg.sampleRate = 48_000
        cfg.channelCount = 1
        cfg.captureMicrophone = includeMic
        if videoURL != nil {
            let scale = CGFloat(SCShareableContent.info(for: filter).pointPixelScale)
            cfg.width = Int(CGFloat(display.width) * scale)
            cfg.height = Int(CGFloat(display.height) * scale)
            cfg.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        } else {
            // SCK always needs a video side; keep it as tiny and slow as possible.
            cfg.width = 2
            cfg.height = 2
            cfg.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        }
        let s = SCStream(filter: filter, configuration: cfg, delegate: nil)
        try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try s.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue) // silences "output NOT found" log spam
        if let videoURL {
            let rc = SCRecordingOutputConfiguration()
            rc.outputURL = videoURL
            rc.outputFileType = .mov
            rc.videoCodecType = .hevc
            try s.addRecordingOutput(SCRecordingOutput(configuration: rc, delegate: self))
        }
        try await s.startCapture()
        stream = s
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        print("ERROR screen recording:", error)
    }

    func stop() async {
        try? await stream?.stopCapture()
        stream = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        let source: Source
        switch type {
        case .audio: source = .system
        case .microphone: source = .mic
        default: return
        }
        guard sb.isValid, let desc = sb.formatDescription else { return }
        let format = AVAudioFormat(cmAudioFormatDescription: desc)
        let frames = AVAudioFrameCount(sb.numSamples)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
        buf.frameLength = frames
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sb, at: 0, frameCount: Int32(frames), into: buf.mutableAudioBufferList) == noErr else { return }
        onBuffer?(buf, source)

        let now = DispatchTime.now().uptimeNanoseconds
        if now - (lastLevel[source] ?? 0) > 66_000_000, let ch = buf.floatChannelData?[0] {
            lastLevel[source] = now
            var rms: Float = 0
            vDSP_rmsqv(ch, 1, &rms, vDSP_Length(frames))
            onLevel?(source, rms)
        }
    }
}

struct Err: LocalizedError {
    let errorDescription: String?
    init(_ s: String) { errorDescription = s }
}
