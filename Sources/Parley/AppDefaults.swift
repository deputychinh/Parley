import Foundation

/// Settings store. A sandboxed run (`--data-dir` / `PARLEY_DATA_DIR`: screenshots, reviews, manual checks) uses its own
/// throw-away defaults domain, so it never reads or changes the owner's settings, and it never schedules reminders.
enum AppDefaults {
    static let sandboxSuite = "parley.sandbox"

    nonisolated static func isSandbox(args: [String], env: [String: String]) -> Bool {
        Model.dataDirFlag(args) != nil || !(env["PARLEY_DATA_DIR"] ?? "").isEmpty
    }

    nonisolated static let sandboxed = isSandbox(args: CommandLine.arguments, env: ProcessInfo.processInfo.environment)

    /// `.standard` for the owner; a fresh `parley.sandbox` domain (wiped at launch) for sandboxed runs.
    nonisolated(unsafe) static let store: UserDefaults = {
        guard sandboxed, let d = UserDefaults(suiteName: sandboxSuite) else { return .standard }
        d.removePersistentDomain(forName: sandboxSuite)
        return d
    }()
}
