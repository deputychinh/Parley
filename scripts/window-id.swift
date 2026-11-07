// Prints the CGWindowID of the largest on-screen window owned by a process name (for `screencapture -l`).
import CoreGraphics
import Foundation

let owner = CommandLine.arguments.dropFirst().first ?? "Parley"
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
func area(_ w: [String: Any]) -> Double {
    let r = w[kCGWindowBounds as String] as? [String: Double] ?? [:]
    return (r["Width"] ?? 0) * (r["Height"] ?? 0)
}
let best = list.filter { ($0[kCGWindowOwnerName as String] as? String) == owner && ($0[kCGWindowLayer as String] as? Int) == 0 }
    .max { area($0) < area($1) }
guard let id = best?[kCGWindowNumber as String] as? Int else { exit(1) }
print(id)
