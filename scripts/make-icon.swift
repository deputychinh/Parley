// Renders the white foreground glyph for AppIcon.icon (background gradient lives in AppIcon.icon/icon.json).
// Usage: swift scripts/make-icon.swift AppIcon.icon/Assets/glyph.png
import AppKit

let size: CGFloat = 1024
let cfg = NSImage.SymbolConfiguration(pointSize: 520, weight: .semibold)
    .applying(.init(paletteColors: [.white]))
let glyph = NSImage(systemSymbolName: "translate", accessibilityDescription: nil)!.withSymbolConfiguration(cfg)!

let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let g = glyph.size
glyph.draw(in: NSRect(x: (size - g.width) / 2, y: (size - g.height) / 2, width: g.width, height: g.height))
img.unlockFocus()

let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
