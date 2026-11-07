import AppKit
import SwiftUI

struct TranscriptLine {
    let time: String
    let source: Source
    let text: String
    let counterpart: String // the same sentence in the other language
}

extension NSAttributedString.Key {
    static let parleyLine = NSAttributedString.Key("parleyLine") // line index on sentence text; -1 for live text
}

/// Selectable transcript backed by NSTextView. Only changed paragraphs are rewritten, so a selection
/// survives live updates; finishing a selection opens a WordCard popover (translate, listen, save).
struct TranscriptView: NSViewRepresentable {
    let lines: [TranscriptLine]
    var live: [(Source, String)] = []
    let language: Locale.Language // language of `text`
    let other: Locale.Language    // language of `counterpart`
    var isSource = true           // true for the heard-language column (what the user is learning)
    let session: String?
    let vocab: VocabStore
    var placeholder = "…"
    var highlighted: Int?                 // line being played back
    var onLineClick: ((Int) -> Void)?     // click (no selection) on a line
    var showMeta = true                   // source icon + time above each paragraph (off for reading passages)
    @AppStorage("fontSize") private var fontSize = 17.0

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let tv = SelectableTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 20, height: 18)
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        tv.selectedTextAttributes = [.backgroundColor: NSColor(Color.parley).withAlphaComponent(0.25)]
        tv.onSelectionEnd = { [weak tv, coordinator = context.coordinator] event in
            guard let tv else { return }
            if tv.selectedRange().length > 0 { coordinator.lookUp(in: tv) } else { coordinator.click(event, in: tv) }
        }
        let scroll = NSScrollView()
        scroll.documentView = tv
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        c.parent = self
        guard let tv = scroll.documentView as? NSTextView, let storage = tv.textStorage else { return }
        if c.fontSize != fontSize { c.fontSize = fontSize; c.sigs = [] }

        let sigs = lines.indices.map { "\(lines[$0].source)|\(lines[$0].time)|\(lines[$0].text)|\($0 == highlighted)" }
            + live.map { "live|\($0.0)|\($0.1)" }
        var k = 0
        while k < min(sigs.count, c.sigs.count), sigs[k] == c.sigs[k] { k += 1 }
        if k == sigs.count, k == c.sigs.count { return }

        let atBottom = scroll.contentView.bounds.maxY >= tv.frame.height - 60
        let start = k == 0 ? 0 : (k < c.offsets.count ? c.offsets[k] : storage.length)
        let tail = NSMutableAttributedString()
        var offsets = Array(c.offsets.prefix(k))
        for i in k..<sigs.count {
            offsets.append(start + tail.length)
            tail.append(i < lines.count ? paragraph(lines[i], index: i) : liveParagraph(live[i - lines.count]))
        }
        storage.replaceCharacters(in: NSRange(location: start, length: storage.length - start), with: tail)
        c.sigs = sigs
        c.offsets = offsets
        if let h = highlighted, h < offsets.count, h != c.lastHighlight {
            tv.scrollRangeToVisible(NSRange(location: offsets[h], length: 0)) // follow playback
        } else if atBottom, highlighted == nil, showMeta { // a reading passage starts at the top
            tv.scrollToEndOfDocument(nil)
        }
        c.lastHighlight = highlighted
        if isSource, !c.debugSelected, let word = DebugArgs.value("--select") {
            let r = (storage.string as NSString).range(of: word)
            if r.location != NSNotFound {
                c.debugSelected = true
                tv.setSelectedRange(r)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { c.lookUp(in: tv) }
            }
        }
    }

    // MARK: Styling

    private var style: NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.paragraphSpacing = fontSize * 0.9
        p.lineHeightMultiple = 1.18
        return p
    }

    private func meta(_ source: Source, _ caption: String) -> NSAttributedString {
        let small = fontSize * 0.66
        let icon = NSTextAttachment()
        icon.image = NSImage(systemSymbolName: source.symbol, accessibilityDescription: source.label)?
            .withSymbolConfiguration(.init(pointSize: small, weight: .semibold).applying(.init(paletteColors: [source.nsColor])))
        let s = NSMutableAttributedString(attachment: icon)
        s.append(NSAttributedString(string: "  \(caption)\u{2028}", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: small, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
            .kern: 0.3,
        ]))
        return s
    }

    private func paragraph(_ l: TranscriptLine, index: Int) -> NSAttributedString {
        let p = NSMutableAttributedString(attributedString: showMeta ? meta(l.source, l.time) : NSAttributedString())
        p.append(NSAttributedString(string: l.text.isEmpty ? placeholder : l.text, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: l.text.isEmpty ? NSColor.tertiaryLabelColor : NSColor.labelColor,
            .parleyLine: index,
        ]))
        p.append(NSAttributedString(string: "\n"))
        p.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: p.length))
        if index == highlighted {
            p.addAttribute(.backgroundColor, value: NSColor(Color.parley).withAlphaComponent(0.16), range: NSRange(location: 0, length: p.length - 1))
        }
        return p
    }

    private func liveParagraph(_ item: (Source, String)) -> NSAttributedString {
        let p = NSMutableAttributedString(attributedString: meta(item.0, "đang nói…"))
        p.append(NSAttributedString(string: item.1, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: NSColor.labelColor,
            .parleyLine: -1,
        ]))
        p.append(NSAttributedString(string: " ▍\n", attributes: [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: NSColor(Color.parley)]))
        p.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: p.length))
        return p
    }

    // MARK: Selection → popover

    @MainActor final class Coordinator {
        var parent: TranscriptView?
        var sigs: [String] = []
        var offsets: [Int] = []
        var fontSize = 0.0
        var lastHighlight: Int?
        var debugSelected = false
        private let popover = NSPopover()

        func click(_ event: NSEvent, in tv: NSTextView) {
            guard let onLineClick = parent?.onLineClick, let storage = tv.textStorage, storage.length > 0 else { return }
            let i = tv.characterIndexForInsertion(at: tv.convert(event.locationInWindow, from: nil))
            guard i < storage.length else { return }
            // Clicks on the time/icon row land outside the sentence attribute: search the rest of that paragraph.
            let para = (storage.string as NSString).paragraphRange(for: NSRange(location: i, length: 0))
            var line: Int?
            storage.enumerateAttribute(.parleyLine, in: para) { v, _, stop in if let v = v as? Int, v >= 0 { line = v; stop.pointee = true } }
            if let line { onLineClick(line) }
        }

        func lookUp(in tv: NSTextView) {
            guard let parent, let storage = tv.textStorage, let window = tv.window else { return }
            let r = tv.selectedRange()
            print("DEBUG lookUp selection", r)
            guard r.length > 0, r.length <= 200 else { return }
            var term = ""
            var lineIndex: Int?
            storage.enumerateAttribute(.parleyLine, in: r) { value, sub, _ in
                guard let i = value as? Int else { return }
                term += (storage.string as NSString).substring(with: sub)
                lineIndex = lineIndex ?? i
            }
            term = term.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            print("DEBUG lookUp term=\(term) line=\(lineIndex.map(String.init) ?? "nil")")
            guard !term.isEmpty, let i = lineIndex else { return }
            let line = parent.lines.indices.contains(i) ? parent.lines[i] : nil
            let card = WordCard(term: term, language: parent.language, other: parent.other, isSource: parent.isSource, context: line?.text ?? "",
                                contextOther: line?.counterpart ?? "", session: parent.session, vocab: parent.vocab)
            let host = NSHostingController(rootView: card)
            host.sizingOptions = .preferredContentSize
            popover.contentViewController = host
            popover.behavior = .transient
            popover.animates = true
            let screenRect = tv.firstRect(forCharacterRange: r, actualRange: nil)
            let rect = tv.convert(window.convertFromScreen(screenRect), from: nil)
            popover.show(relativeTo: rect, of: tv, preferredEdge: .maxY)
        }
    }
}

final class SelectableTextView: NSTextView {
    var onSelectionEnd: ((NSEvent) -> Void)?
    // NSTextView tracks the drag inside mouseDown; when it returns, the selection is final.
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        onSelectionEnd?(event)
    }
}
