import Foundation

/// Settings store. A sandboxed run (`--data-dir` / `PARLEY_DATA_DIR`: screenshots, reviews, manual checks) uses its own
/// throw-away defaults domain, so it never reads or changes the owner's settings, and it never schedules reminders.
enum AppDefaults {
    /// One domain per sandboxed process, so parallel screenshot / review runs never wipe each other's settings.
    nonisolated static let sandboxSuite = "parley.sandbox.\(ProcessInfo.processInfo.processIdentifier)"

    nonisolated static func isSandbox(args: [String], env: [String: String]) -> Bool {
        Model.dataDirFlag(args) != nil || !(env["PARLEY_DATA_DIR"] ?? "").isEmpty
    }

    nonisolated static let sandboxed = isSandbox(args: CommandLine.arguments, env: ProcessInfo.processInfo.environment)

    /// Domains left behind by earlier sandboxed runs (killed instances never reach `applicationWillTerminate`).
    nonisolated static func staleSandboxDomains(fileNames: [String], own: String) -> [String] {
        fileNames.filter { $0.hasPrefix("parley.sandbox") && $0.hasSuffix(".plist") }.map { String($0.dropLast(".plist".count)) }
            .filter { $0 != own }
    }

    /// At launch of a sandboxed run: remove the domains earlier sandboxed runs left in ~/Library/Preferences.
    static func removeStaleSandboxDomains() {
        guard sandboxed else { return }
        let prefs = URL.libraryDirectory.appending(path: "Preferences")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: prefs.path)) ?? []
        for domain in staleSandboxDomains(fileNames: names, own: sandboxSuite) { UserDefaults.standard.removePersistentDomain(forName: domain) }
    }

    /// When a sandboxed run quits normally, its own domain goes too.
    static func removeOwnSandboxDomain() {
        guard sandboxed else { return }
        UserDefaults.standard.removePersistentDomain(forName: sandboxSuite)
    }

    /// `.standard` for the owner; a fresh `parley.sandbox.<pid>` domain for sandboxed runs.
    nonisolated(unsafe) static let store: UserDefaults = {
        guard sandboxed, let d = UserDefaults(suiteName: sandboxSuite) else { return .standard }
        d.removePersistentDomain(forName: sandboxSuite)
        return d
    }()
}
