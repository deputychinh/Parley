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

    /// The owner's real app must not run sandboxed: macOS would still save its window frames under the owner's
    /// bundle id. Manual and scripted `--data-dir` runs use `build/Parley-sandbox.app` (`make sandbox-app`).
    nonisolated static func refusesSandboxedRun(bundleID: String?, sandboxed: Bool) -> Bool {
        sandboxed && bundleID == "com.david.parley"
    }

    /// Domains left by sandboxed runs that are gone: `parley.sandbox.<pid>` whose process no longer exists (never a
    /// running instance's), plus the old shared `parley.sandbox`.
    nonisolated static func staleSandboxDomains(fileNames: [String], own: String, isAlive: (Int32) -> Bool) -> [String] {
        fileNames.filter { $0.hasPrefix("parley.sandbox") && $0.hasSuffix(".plist") }
            .map { String($0.dropLast(".plist".count)) }
            .filter { domain in
                guard domain != own else { return false }
                guard domain.hasPrefix("parley.sandbox."), let pid = Int32(domain.dropFirst("parley.sandbox.".count)) else { return true }
                return !isAlive(pid)
            }
    }

    nonisolated static func processIsAlive(_ pid: Int32) -> Bool { kill(pid, 0) == 0 || errno == EPERM }

    /// Empties a sandbox domain and deletes its file (removePersistentDomain alone leaves an empty plist behind).
    nonisolated static func removeDomain(_ domain: String, prefs: URL = URL.libraryDirectory.appending(path: "Preferences")) {
        UserDefaults.standard.removePersistentDomain(forName: domain)
        try? FileManager.default.removeItem(at: prefs.appending(path: domain + ".plist"))
    }

    /// At launch of a sandboxed run: remove what earlier, finished sandboxed runs left in ~/Library/Preferences.
    static func removeStaleSandboxDomains() {
        guard sandboxed else { return }
        let prefs = URL.libraryDirectory.appending(path: "Preferences")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: prefs.path)) ?? []
        for domain in staleSandboxDomains(fileNames: names, own: sandboxSuite, isAlive: processIsAlive) { removeDomain(domain, prefs: prefs) }
    }

    /// When a sandboxed run ends (quit or SIGTERM from shot.sh), its own domain goes too.
    static func removeOwnSandboxDomain() {
        guard sandboxed else { return }
        removeDomain(sandboxSuite)
    }

    /// shot.sh stops its instance with SIGTERM, which skips `applicationWillTerminate`: clean up, then exit.
    nonisolated(unsafe) private static var termSource: DispatchSourceSignal?
    static func cleanUpOnSIGTERM() {
        guard sandboxed else { return }
        signal(SIGTERM, SIG_IGN)
        let s = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        s.setEventHandler { removeOwnSandboxDomain(); exit(0) }
        s.resume()
        termSource = s
    }

    /// `.standard` for the owner; a fresh `parley.sandbox.<pid>` domain for sandboxed runs.
    nonisolated(unsafe) static let store: UserDefaults = {
        guard sandboxed, let d = UserDefaults(suiteName: sandboxSuite) else { return .standard }
        d.removePersistentDomain(forName: sandboxSuite)
        return d
    }()
}
