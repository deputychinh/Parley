import Foundation
import SwiftUI

/// A run of Japanese text, with its hiragana reading when it contains kanji.
struct RubySegment: Equatable, Sendable {
    var text: String
    var reading: String?
}

/// Kana readings (furigana) for Japanese text, on device: CFStringTokenizer's Latin transcription turned into hiragana.
enum Furigana {
    /// The whole text split into segments; only runs with kanji get a reading, and kana written next to the kanji
    /// (okurigana, e.g. 始**めましょう**) stay outside it.
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
            let latin = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String
            out += split(word, reading: latin.flatMap { hiragana($0) })
            cursor = range.location + range.length
        }
        if cursor < ns.length { out.append(RubySegment(text: ns.substring(from: cursor))) }
        return merge(out)
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

    /// Neighbouring segments without a reading become one (fewer views to lay out).
    nonisolated static func merge(_ segments: [RubySegment]) -> [RubySegment] {
        segments.reduce(into: []) { out, s in
            if s.reading == nil, let last = out.last, last.reading == nil { out[out.count - 1].text += s.text } else { out.append(s) }
        }
    }

    nonisolated static func isKanji(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value else { return false }
        return (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) || (0xF900...0xFAFF).contains(v) || v == 0x3005 // 々
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
}

/// Japanese text with small readings above its kanji, wrapping like a paragraph.
struct RubyText: View {
    let segments: [RubySegment]
    var font: Font = .callout

    var body: some View {
        WrapLayout {
            ForEach(Array(pieces.enumerated()), id: \.offset) { _, piece in
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

    /// Text without a reading is cut into single characters so a long run can still wrap.
    private var pieces: [RubySegment] {
        segments.flatMap { s in s.reading == nil ? s.text.map { RubySegment(text: String($0)) } : [s] }
    }
}

/// Lays children left to right and starts a new line when the width runs out.
struct WrapLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: rows.map(\.width).max() ?? 0, height: rows.reduce(0) { $0 + $1.height })
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + row.height - size.height), proposal: .unspecified)
                x += size.width
            }
            y += row.height
        }
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            if rows[rows.count - 1].width + size.width > width, !rows[rows.count - 1].items.isEmpty { rows.append(Row()) }
            rows[rows.count - 1].items.append(i)
            rows[rows.count - 1].width += size.width
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}
