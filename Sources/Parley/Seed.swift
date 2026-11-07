import Foundation

/// `Parley --seed <dir>`: writes realistic sample data for screenshots and manual checks.
/// Refuses the real data folder so a typo can never overwrite the user's words.
enum Seed {
    static func write(to dir: URL) throws {
        let real = URL.documentsDirectory.appending(path: "Parley").standardizedFileURL
        guard dir.standardizedFileURL != real else { throw Err("refusing to seed the real data folder \(real.path)") }
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
        try e.encode(items).write(to: dir.appending(path: "vocabulary.json"))

        let lines: [(String, String, Double)] = [
            ("Good morning everyone, let's start the weekly sync.", "Chào buổi sáng mọi người, hãy bắt đầu buổi họp tuần.", 0.5),
            ("We found a memory leak in the payment service yesterday.", "Hôm qua chúng tôi tìm thấy rò rỉ bộ nhớ trong dịch vụ thanh toán.", 4.6),
            ("The fix is ready, but we need one more day to test it.", "Bản sửa đã sẵn sàng, nhưng cần thêm một ngày để kiểm thử.", 9.4),
            ("Can we move the deadline to Friday?", "Chúng ta có thể dời hạn chót sang thứ Sáu không?", 14.0),
            ("Sure, I will follow up with the stakeholders after this call.", "Được, tôi sẽ trao đổi tiếp với các bên liên quan sau cuộc gọi.", 17.2),
        ]
        var md = "# Parley — \(sessionStamp)\n<!-- parley: en_US > vi -->\n\nGhi âm: `\(sessionStamp)-may.m4a` (âm thanh máy)\n\n"
        for (i, l) in lines.enumerated() {
            md += "**9:30:\(String(format: "%02d", 12 + i * 4)) AM** 🔊 \(l.0) <!-- t=\(l.2) -->\n> \(l.1)\n\n"
        }
        try Data(md.utf8).write(to: dir.appending(path: "\(sessionStamp).md"))
    }

    static let sessionStamp = "2026-11-06_09-30-12"
}
