import Foundation
import SwiftUI

/// A run of Japanese text, with its hiragana reading when it contains kanji.
struct RubySegment: Equatable, Sendable {
    var text: String
    var reading: String?
}

/// Kana readings (furigana) for Japanese text, on device: CFStringTokenizer's Latin transcription turned into hiragana.
enum Furigana {
    /// Readings are drawn word by word; above this many characters (all paragraphs together) they are skipped, so a
    /// long text never stalls the window.
    nonisolated static let limit = 1_000

    /// The whole text as word-sized segments; only runs with kanji get a reading, kana written next to the kanji
    /// (okurigana, e.g. 始**めましょう**) stays outside it, and a word right after a digit (3月14日: a counter whose
    /// reading the dictionary gets wrong) gets none.
    nonisolated static func segments(_ text: String) -> [RubySegment] {
        guard !text.isEmpty else { return [] }
        let ns = text as NSString
        let tokenizer = CFStringTokenizerCreate(nil, text as CFString, CFRange(location: 0, length: ns.length),
                                                kCFStringTokenizerUnitWord, Locale(identifier: "ja") as CFLocale)
        var out: [RubySegment] = []
        var cursor = 0
        while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            if range.location > cursor { out.append(RubySegment(text: ns.substring(with: NSRange(location: cursor, length: range.location - cursor)))) }
            let word = ns.substring(with: NSRange(location: range.location, length: range.length))
            let afterDigit = range.location > 0 && isDigit(ns.character(at: range.location - 1))
            let latin = afterDigit ? nil : CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String
            out += split(word, reading: latin.flatMap { hiragana($0) })
            cursor = range.location + range.length
        }
        if cursor < ns.length { out.append(RubySegment(text: ns.substring(from: cursor))) }
        return out
    }

    /// `word` with its full reading → kana prefix, kanji core with the remaining reading, kana suffix.
    nonisolated static func split(_ word: String, reading: String?) -> [RubySegment] {
        guard word.contains(where: isKanji), let reading, !reading.isEmpty else { return [RubySegment(text: word)] }
        let chars = Array(word)
        guard let first = chars.firstIndex(where: isKanji), let last = chars.lastIndex(where: isKanji) else { return [RubySegment(text: word)] }
        let prefix = String(chars[..<first]), core = String(chars[first...last]), suffix = String(chars[(last + 1)...])
        let whole = [RubySegment(text: word, reading: reading)]
        var r = reading
        if !prefix.isEmpty {
            guard let p = hiragana(kana: prefix), r.hasPrefix(p) else { return whole }
            r.removeFirst(p.count)
        }
        if !suffix.isEmpty {
            guard let s = hiragana(kana: suffix), r.hasSuffix(s), r.count > s.count else { return whole }
            r.removeLast(s.count)
        }
        guard !r.isEmpty else { return whole }
        return [RubySegment(text: prefix), RubySegment(text: core, reading: r), RubySegment(text: suffix)].filter { !$0.text.isEmpty }
    }

    /// CJK ideographs, including the extension blocks beyond U+FFFF (𠮷), and the repeat mark 々.
    nonisolated static func isKanji(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value else { return false }
        return (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) || (0xF900...0xFAFF).contains(v)
            || (0x20000...0x3134F).contains(v) || v == 0x3005
    }

    /// ASCII or full-width digit (one UTF-16 unit).
    nonisolated static func isDigit(_ unit: unichar) -> Bool {
        (0x30...0x39).contains(unit) || (0xFF10...0xFF19).contains(unit)
    }

    /// Latin transcription → hiragana; nil when letters are left over (the transcription did not convert cleanly).
    nonisolated static func hiragana(_ latin: String) -> String? {
        let m = NSMutableString(string: latin)
        guard CFStringTransform(m, nil, kCFStringTransformLatinHiragana, false) else { return nil }
        let s = m as String
        return s.unicodeScalars.contains(where: { $0.isASCII && $0.properties.isAlphabetic }) ? nil : s
    }

    /// Kana text as hiragana (katakana converted); nil when it is not all kana.
    nonisolated static func hiragana(kana: String) -> String? {
        let m = NSMutableString(string: kana)
        guard CFStringTransform(m, nil, kCFStringTransformHiraganaKatakana, true) else { return nil }
        let s = m as String
        return s.unicodeScalars.allSatisfy({ (0x3040...0x309F).contains($0.value) || $0.value == 0x30FC }) ? s : nil
    }

    /// Pieces the view lays out: one per word; a long run without a reading (a URL, a long Latin word) is cut into
    /// characters so it can still wrap.
    nonisolated static func pieces(_ segments: [RubySegment], longest: Int = 12) -> [RubySegment] {
        segments.flatMap { s in s.reading == nil && s.text.count > longest ? s.text.map { RubySegment(text: String($0)) } : [s] }
    }
}

/// Japanese text with small readings above its kanji, wrapping like a paragraph.
struct RubyText: View {
    let segments: [RubySegment]
    var font: Font = .callout

    var body: some View {
        WrapLayout {
            ForEach(Array(Furigana.pieces(segments).enumerated()), id: \.offset) { _, piece in
                VStack(spacing: 0) {
                    Text(piece.reading ?? " ").font(.caption2).foregroundStyle(.secondary).opacity(piece.reading == nil ? 0 : 1)
                    Text(piece.text).font(font)
                }
                .fixedSize()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(segments.map(\.text).joined())
    }
}

/// Lays children left to right and starts a new line when the width runs out. Child sizes are measured once per
/// change of children (cache), not on every layout pass.
struct WrapLayout: Layout {
    func makeCache(subviews: Subviews) -> [CGSize] { subviews.map { $0.sizeThatFits(.unspecified) } }

    func updateCache(_ cache: inout [CGSize], subviews: Subviews) { cache = makeCache(subviews: subviews) }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout [CGSize]) -> CGSize {
        let rows = Self.rows(width: proposal.width ?? .infinity, sizes: cache)
        return CGSize(width: rows.map(\.width).max() ?? 0, height: rows.reduce(0) { $0 + $1.height })
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout [CGSize]) {
        var y = bounds.minY
        for row in Self.rows(width: bounds.width, sizes: cache) {
            var x = bounds.minX
            for i in row.items {
                subviews[i].place(at: CGPoint(x: x, y: y + row.height - cache[i].height), proposal: .unspecified)
                x += cache[i].width
            }
            y += row.height
        }
    }

    struct Row: Equatable { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    /// Greedy line breaking; an item wider than the line gets a line of its own.
    nonisolated static func rows(width: CGFloat, sizes: [CGSize]) -> [Row] {
        var rows: [Row] = [Row()]
        for (i, size) in sizes.enumerated() {
            if rows[rows.count - 1].width + size.width > width, !rows[rows.count - 1].items.isEmpty { rows.append(Row()) }
            rows[rows.count - 1].items.append(i)
            rows[rows.count - 1].width += size.width
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}
