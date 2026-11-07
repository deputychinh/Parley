import Foundation

/// One JSON file per store (CLAUDE.md). Loading never loses data: an unreadable file is moved aside to a unique
/// name, and if it cannot be moved the store becomes read-only so a later save can't overwrite it.
enum StoreFile {
    struct Loaded<T> {
        var value: T?
        var writable: Bool
        var problem: String?   // shown to the user when the file was unreadable or couldn't be moved aside
    }

    static func load<T: Decodable>(_ type: T.Type, from url: URL, decoder: JSONDecoder = JSONDecoder(),
                                   fm: FileManager = .default, now: Date = .now) -> Loaded<T> {
        let data: Data
        do { data = try Data(contentsOf: url) } catch let e as CocoaError where e.code == .fileReadNoSuchFile {
            return Loaded(value: nil, writable: true) // first launch
        } catch {
            return Loaded(value: nil, writable: false, problem: "Không đọc được \(url.lastPathComponent): \(error.localizedDescription)")
        }
        do {
            return Loaded(value: try decoder.decode(T.self, from: data), writable: true)
        } catch {
            let aside = asideURL(for: url, now: now)
            do {
                try fm.moveItem(at: url, to: aside)
                return Loaded(value: nil, writable: true,
                              problem: "\(url.lastPathComponent) bị hỏng nên đã được cất sang \(aside.lastPathComponent); dữ liệu cũ vẫn còn đó.")
            } catch {
                return Loaded(value: nil, writable: false,
                              problem: "\(url.lastPathComponent) bị hỏng và không cất sang chỗ khác được, nên Parley sẽ không ghi đè lên nó.")
            }
        }
    }

    /// `vocabulary.json` → `vocabulary.unreadable-20261108-101500-1a2b3c.json`, never an existing name.
    static func asideURL(for url: URL, now: Date) -> URL {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        let tag = UUID().uuidString.prefix(6).lowercased()
        return url.deletingPathExtension().appendingPathExtension("unreadable-\(f.string(from: now))-\(tag).json")
    }

    static func save<T: Encodable>(_ value: T, to url: URL, encoder: JSONEncoder) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
