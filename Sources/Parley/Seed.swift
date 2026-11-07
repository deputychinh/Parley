import AVFoundation
import Foundation

/// `Parley --seed <dir>`: writes realistic sample data for screenshots and manual checks.
/// Refuses the real data folder so a typo can never overwrite the user's words.
enum Seed {
    /// The owner's data folder; nothing is ever seeded in or under it.
    static let realFolder = URL.documentsDirectory.appending(path: "Parley")

    /// Seeding is allowed only into a missing or empty folder outside `real` (compared after resolving symlinks,
    /// `.`/`..`, trailing slashes and letter case — APFS is case-insensitive by default).
    nonisolated static func isAllowed(_ dir: URL, real: URL = realFolder, fm: FileManager = .default) -> Bool {
        // Case-folded because a folder that doesn't exist yet keeps the typed case after resolving.
        func key(_ u: URL) -> String { u.resolvingSymlinksInPath().standardizedFileURL.path.lowercased() }
        let d = key(dir), r = key(real)
        guard d != r, !d.hasPrefix(r + "/"), !r.hasPrefix(d + "/") else { return false } // also refuse ~/Documents itself
        do {
            return try fm.contentsOfDirectory(atPath: dir.path).isEmpty
        } catch let e as CocoaError where e.code == .fileReadNoSuchFile {
            return true // missing → will be created
        } catch {
            return false // unreadable or not a folder → never assume it is safe
        }
    }

    /// The folder after `--seed`; nil when it is missing or another flag follows.
    nonisolated static func folder(in args: [String]) -> URL? {
        guard let i = args.firstIndex(of: "--seed"), args.indices.contains(i + 1), !args[i + 1].hasPrefix("--"),
              !args[i + 1].isEmpty else { return nil }
        return URL(fileURLWithPath: args[i + 1])
    }

    /// `audio`: also record the session with the system voice (`say`), so listening practice has real clips.
    static func write(to dir: URL, audio: Bool = true) throws {
        guard isAllowed(dir) else { throw Err("refusing to seed \(dir.path): use a new empty folder outside \(realFolder.path)") }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let words: [(String, String, String)] = [
            ("deadline", "hạn chót", "We need to move the deadline to Friday."),
            ("leak", "rò rỉ", "There is a memory leak in the payment service."),
            ("rollback", "khôi phục bản trước", "Let's do a rollback before the traffic peak."),
            ("stakeholder", "bên liên quan", "Every stakeholder should review the plan."),
            ("bottleneck", "nút thắt cổ chai", "The database is the real bottleneck here."),
            ("deploy", "triển khai", "We deploy to production every Tuesday."),
            ("estimate", "ước lượng", "Can you estimate the effort for this ticket?"),
            ("follow up", "theo dõi tiếp", "I will follow up with the design team."),
            ("agenda", "chương trình họp", "The first item on the agenda is the release."),
            ("outage", "sự cố ngừng dịch vụ", "The outage lasted about twenty minutes."),
            ("priority", "ưu tiên", "Security fixes are our top priority."),
            ("feedback", "phản hồi", "Thanks for the quick feedback on the draft."),
        ]
        let now = Date()
        let items = words.enumerated().map { i, w in
            var v = VocabItem(term: w.0, meaning: w.1, termLanguage: "en-US", meaningLanguage: "vi", ipa: Pronunciation.ipa(w.0),
                              example: w.2, exampleTranslation: "", session: sessionStamp)
            v.added = now.addingTimeInterval(Double(-i) * 86_400)
            if i % 3 == 0 { for _ in 0..<5 { v.review(correct: true, now: now) } } else if i % 3 == 1 { v.review(correct: true, now: now) }
            return v
        }
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        try e.encode(items).write(to: dir.appending(path: "vocabulary.json"), options: .atomic)

        var lines: [(String, String, Double)] = [
            ("Good morning everyone, let's start the weekly sync.", "Chào buổi sáng mọi người, hãy bắt đầu buổi họp tuần.", 0.5),
            ("We found a memory leak in the payment service yesterday.", "Hôm qua chúng tôi tìm thấy rò rỉ bộ nhớ trong dịch vụ thanh toán.", 4.6),
            ("The fix is ready, but we need one more day to test it.", "Bản sửa đã sẵn sàng, nhưng cần thêm một ngày để kiểm thử.", 9.4),
            ("Can we move the deadline to Friday?", "Chúng ta có thể dời hạn chót sang thứ Sáu không?", 14.0),
            ("Sure, I will follow up with the stakeholders after this call.", "Được, tôi sẽ trao đổi tiếp với các bên liên quan sau cuộc gọi.", 17.2),
        ]
        if audio {
            let offsets = try record(lines.map(\.0), to: dir.appending(path: "\(sessionStamp)-may.m4a"))
            for i in lines.indices { lines[i].2 = offsets[i] }
        }
        var md = "# Parley — \(sessionStamp)\n<!-- parley: en_US > vi -->\n\nGhi âm: `\(sessionStamp)-may.m4a` (âm thanh máy)\n\n"
        for (i, l) in lines.enumerated() {
            md += "**9:30:\(String(format: "%02d", 12 + i * 4)) AM** 🔊 \(l.0) <!-- t=\(l.2) -->\n> \(l.1)\n\n"
        }
        try Data(md.utf8).write(to: dir.appending(path: "\(sessionStamp).md"), options: .atomic)
        try e.encode(sampleActivity(now: now)).write(to: dir.appending(path: "activity.json"), options: .atomic)
    }

    /// ~10 weeks of study: today under way (30/50), the 6 days before met the goal, scattered days earlier.
    static func sampleActivity(now: Date) -> ActivityData {
        var a = ActivityData()
        let mix: [Skill] = [.vocabulary, .grammar, .listening, .speaking]
        for back in 0..<70 {
            let day = StudyStore.day(now.addingTimeInterval(Double(-back) * 86_400))
            let xp = back == 0 ? 30 : back <= 6 ? 50 + (back * 13) % 40 : (back % 3 == 0 ? 0 : (back * 17) % 70)
            guard xp > 0 else { continue }
            var skills: [String: Int] = [:]
            for (i, s) in mix.enumerated() where (back + i) % 2 == 0 || i == 0 { skills[s.rawValue] = xp / 2 / (i + 1) + 2 }
            let scale = Double(xp) / Double(skills.values.reduce(0, +))
            for k in skills.keys { skills[k] = Int((Double(skills[k]!) * scale).rounded()) }
            skills[Skill.vocabulary.rawValue, default: 0] += xp - skills.values.reduce(0, +) // exact total
            a.days[day] = skills
            if xp >= a.goal { a.met.append(day) }
        }
        return a
    }

    static let sessionStamp = "2026-11-06_09-30-12"

    /// Speaks each sentence with `say` into one AAC file (0.6 s gap) and returns where each sentence starts.
    private static func record(_ sentences: [String], to url: URL) throws -> [Double] {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "parley-say-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        var out: AVAudioFile?
        var offsets: [Double] = []
        var written: AVAudioFramePosition = 0
        for (i, s) in sentences.enumerated() {
            let part = tmp.appending(path: "\(i).aiff")
            let say = Process()
            say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            say.arguments = ["-o", part.path, s]
            try say.run()
            say.waitUntilExit()
            guard say.terminationStatus == 0 else { throw Err("say failed for sentence \(i)") }
            let input = try AVAudioFile(forReading: part)
            let format = input.processingFormat
            if out == nil {
                out = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: format.sampleRate,
                                                                  AVNumberOfChannelsKey: format.channelCount],
                                      commonFormat: format.commonFormat, interleaved: format.isInterleaved)
            }
            guard let out, let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(input.length)),
                  let gap = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(format.sampleRate * 0.6)) else {
                throw Err("audio buffers")
            }
            try input.read(into: buf)
            offsets.append(Double(written) / format.sampleRate)
            try out.write(from: buf)
            gap.frameLength = gap.frameCapacity // zero-filled = silence
            try out.write(from: gap)
            written += AVAudioFramePosition(buf.frameLength + gap.frameLength)
        }
        try? FileManager.default.removeItem(at: tmp)
        return offsets
    }
}
