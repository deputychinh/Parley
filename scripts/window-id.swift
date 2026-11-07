// Prints the CGWindowID of the largest on-screen window of a process (for `screencapture -l`).
// Argument: a PID (preferred — never confuses the owner's own Parley with ours) or a process name.
import CoreGraphics
import Foundation

let arg = CommandLine.arguments.dropFirst().first ?? "Parley"
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
func area(_ w: [String: Any]) -> Double {
    let r = w[kCGWindowBounds as String] as? [String: Double] ?? [:]
    return (r["Width"] ?? 0) * (r["Height"] ?? 0)
}
func owned(_ w: [String: Any]) -> Bool {
    if let pid = Int(arg) { return (w[kCGWindowOwnerPID as String] as? Int) == pid }
    return (w[kCGWindowOwnerName as String] as? String) == arg
}
let best = list.filter { owned($0) && ($0[kCGWindowLayer as String] as? Int) == 0 }.max { area($0) < area($1) }
guard let id = best?[kCGWindowNumber as String] as? Int else { exit(1) }
print(id)
