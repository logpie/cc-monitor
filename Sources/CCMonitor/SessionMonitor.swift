import Foundation
import Combine
import CCMonitorCore

@MainActor
final class SessionMonitor: ObservableObject {
    @Published var sessions: [SessionInfo] = []

    private let monitorDir: URL
    private var dirSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var refreshTimer: Timer?
    private var livenessTimer: Timer?
    private let ioQueue = DispatchQueue(label: "ccmonitor.io", qos: .userInitiated)

    /// Cached liveness results: [sessionId: alive]
    private var livenessCache: [String: Bool] = [:]

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.monitorDir = home.appendingPathComponent(".claude/monitor")
        try? FileManager.default.createDirectory(at: monitorDir, withIntermediateDirectories: true)

        startWatching()
        startPeriodicRefresh()
        startLivenessCheck()
        loadSessionsAsync(checkLiveness: true)
    }

    deinit {
        dirSource?.cancel()
        if fileDescriptor >= 0 { Darwin.close(fileDescriptor) }
        refreshTimer?.invalidate()
        livenessTimer?.invalidate()
    }

    private func startWatching() {
        fileDescriptor = Darwin.open(monitorDir.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename, .extend],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.loadSessionsAsync(checkLiveness: false)
        }
        source.setCancelHandler { [fd = fileDescriptor] in
            Darwin.close(fd)
        }
        source.resume()
        self.dirSource = source
    }

    private func startPeriodicRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.loadSessionsAsync(checkLiveness: false)
            }
        }
    }

    private func startLivenessCheck() {
        livenessTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.loadSessionsAsync(checkLiveness: true)
            }
        }
    }

    /// Trigger an async load on the IO queue, publish results on main thread
    func loadSessions(checkLiveness: Bool = false) {
        loadSessionsAsync(checkLiveness: checkLiveness)
    }

    private func loadSessionsAsync(checkLiveness: Bool) {
        let dir = monitorDir
        let cache = livenessCache

        ioQueue.async { [weak self] in
            let result = Self.loadFromDisk(dir: dir, livenessCache: cache, checkLiveness: checkLiveness)

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.sessions = result.sessions
                self.livenessCache = result.updatedCache

                // Clean up files marked for deletion
                for url in result.toDelete {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
    }

    private struct LoadResult {
        var sessions: [SessionInfo]
        var updatedCache: [String: Bool]
        var toDelete: [URL]
    }

    /// Pure I/O work — runs off main thread
    private nonisolated static func loadFromDisk(
        dir: URL,
        livenessCache: [String: Bool],
        checkLiveness: Bool
    ) -> LoadResult {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else {
            return LoadResult(sessions: [], updatedCache: livenessCache, toDelete: [])
        }

        let now = Date()
        var updatedCache = livenessCache
        var toDelete: [URL] = []
        var sessions: [SessionInfo] = []

        for url in files {
            guard url.pathExtension == "json", !url.lastPathComponent.hasPrefix(".") else { continue }

            guard let data = try? Data(contentsOf: url),
                  var session = try? JSONDecoder().decode(SessionInfo.self, from: data)
            else { continue }

            let age = now.timeIntervalSince1970 - session.lastUpdated

            if shouldCheckLiveness(age: age) {
                if checkLiveness {
                    let alive = isClaudeAlive(on: session.tty)
                    updatedCache[session.sessionId] = alive
                    session.processAlive = alive
                } else {
                    session.processAlive = livenessCache[session.sessionId] ?? true
                }
            }

            let hookState = readHookState(dir: dir, sessionId: session.sessionId)

            switch sessionAction(hookState: hookState, age: age, processAlive: session.processAlive) {
            case .delete:
                toDelete.append(url)
                let stateFile = dir.appendingPathComponent(".\(session.sessionId).state")
                toDelete.append(stateFile)
                updatedCache.removeValue(forKey: session.sessionId)
            case .keep(let status):
                session.cachedStatus = status
                session.hookState = hookState
                sessions.append(session)
            }
        }

        sessions.sort { $0.projectName < $1.projectName }
        return LoadResult(sessions: sessions, updatedCache: updatedCache, toDelete: toDelete)
    }

    private nonisolated static func readHookState(dir: URL, sessionId: String) -> HookState? {
        let stateFile = dir.appendingPathComponent(".\(sessionId).state")
        guard let content = try? String(contentsOf: stateFile, encoding: .utf8) else {
            return nil
        }
        return HookState(rawValue: content.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private nonisolated static func isClaudeAlive(on tty: String?) -> Bool {
        guard let tty = tty, !tty.isEmpty else { return false }
        let short = tty.replacingOccurrences(of: "/dev/", with: "")
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-t", short, "-o", "comm="]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
        } catch { return false }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return output.contains("claude")
    }
}
