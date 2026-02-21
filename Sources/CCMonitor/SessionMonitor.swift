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

    /// Cached Ghostty tab titles: [tty: title]
    private var tabTitleCache: [String: String] = [:]

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
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
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
        let titleCache = tabTitleCache

        ioQueue.async { [weak self] in
            var result = Self.loadFromDisk(dir: dir, livenessCache: cache, checkLiveness: checkLiveness)

            // On liveness check path, also resolve Ghostty tab titles
            if checkLiveness {
                let newTitles = Self.resolveGhosttyTitles(
                    sessions: result.sessions, titleCache: titleCache)
                for i in result.sessions.indices {
                    let tty = result.sessions[i].tty ?? ""
                    if let title = newTitles[tty], !title.isEmpty {
                        result.sessions[i].ghosttyTabTitle = title
                    }
                }
            } else {
                // Apply cached titles
                for i in result.sessions.indices {
                    let tty = result.sessions[i].tty ?? ""
                    if let title = titleCache[tty], !title.isEmpty {
                        result.sessions[i].ghosttyTabTitle = title
                    }
                }
            }

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.sessions = result.sessions
                self.livenessCache = result.updatedCache

                // Update tab title cache
                if checkLiveness {
                    for s in result.sessions {
                        if let tty = s.tty, let title = s.ghosttyTabTitle, !title.isEmpty {
                            self.tabTitleCache[tty] = title
                        }
                    }
                }

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

            let hookData = readHookState(dir: dir, sessionId: session.sessionId)

            switch sessionAction(hookState: hookData.state, age: age, processAlive: session.processAlive) {
            case .delete:
                toDelete.append(url)
                let stateFile = dir.appendingPathComponent(".\(session.sessionId).state")
                toDelete.append(stateFile)
                updatedCache.removeValue(forKey: session.sessionId)
            case .keep(let status):
                session.cachedStatus = status
                session.hookState = hookData.state
                session.hookContext = hookData.context
                session.lastMessage = hookData.lastMessage
                session.activeAgents = hookData.activeAgents
                sessions.append(session)
            }
        }

        sessions.sort { $0.lastUpdated > $1.lastUpdated }
        return LoadResult(sessions: sessions, updatedCache: updatedCache, toDelete: toDelete)
    }

    private nonisolated static func readHookState(dir: URL, sessionId: String) -> HookFileData {
        let stateFile = dir.appendingPathComponent(".\(sessionId).state")
        guard let content = try? String(contentsOf: stateFile, encoding: .utf8) else {
            return HookFileData(state: nil, context: nil, lastMessage: nil)
        }
        return parseHookStateFile(content)
    }

    /// Resolve Ghostty tab titles for non-tmux sessions.
    /// Phase 1: read all tab titles. Phase 2: tag TTYs to match tabs. Phase 3: restore.
    private nonisolated static func resolveGhosttyTitles(
        sessions: [SessionInfo], titleCache: [String: String]
    ) -> [String: String] {
        let needsResolve = sessions.filter { s in
            guard let tty = s.tty, !tty.isEmpty else { return false }
            if let tmux = s.tmuxTarget, !tmux.isEmpty { return false }
            return true
        }
        guard !needsResolve.isEmpty else { return titleCache }

        // Step 1: Read all Ghostty tab titles (before any tagging)
        let allTitles = readAllGhosttyTitles()
        guard !allTitles.isEmpty else { return titleCache }

        // Step 2: Tag each session's TTY with a unique marker
        var ttyToTag: [String: String] = [:]
        for s in needsResolve {
            guard let tty = s.tty else { continue }
            let tag = "ccmon-\(s.sessionId.prefix(8))"
            ttyToTag[tty] = tag
            writeToTTY(tty, "\u{1b}]2;\(tag)\u{07}")
        }

        Thread.sleep(forTimeInterval: 0.05)

        // Step 3: Read tab titles again to find which tab has which tag
        let taggedTitles = readAllGhosttyTitles()

        // Step 4: Restore TTYs (empty title lets shell precmd restore)
        for (tty, _) in ttyToTag {
            writeToTTY(tty, "\u{1b}]2;\u{07}")
        }

        // Step 5: Match tags to original titles by tab position
        var result = titleCache
        for (tty, tag) in ttyToTag {
            // Find which position has our tag in the tagged snapshot
            if let tagIdx = taggedTitles.firstIndex(where: { $0.contains(tag) }) {
                // Same position in the pre-tag snapshot has the original title
                if tagIdx < allTitles.count {
                    result[tty] = allTitles[tagIdx]
                }
            }
        }
        return result
    }

    /// Read all Ghostty tab titles via AppleScript. Returns titles in order.
    private nonisolated static func readAllGhosttyTitles() -> [String] {
        let script = """
        set results to {}
        tell application "System Events"
            if not (exists process "ghostty") then return ""
            tell process "ghostty"
                repeat with w in every window
                    try
                        set tg to UI element "tab bar" of w
                        repeat with t in every radio button of tg
                            set end of results to name of t
                        end repeat
                    on error
                        set end of results to name of w
                    end try
                end repeat
            end tell
        end tell
        set AppleScript's text item delimiters to "||"
        return results as text
        """
        var output = ""
        DispatchQueue.main.sync {
            var error: NSDictionary?
            if let s = NSAppleScript(source: script) {
                let result = s.executeAndReturnError(&error)
                output = result.stringValue ?? ""
            }
        }
        guard !output.isEmpty else { return [] }
        return output.components(separatedBy: "||")
    }

    @discardableResult
    private nonisolated static func writeToTTY(_ tty: String, _ escape: String) -> Bool {
        guard let fh = FileHandle(forWritingAtPath: tty) else { return false }
        fh.write(Data(escape.utf8))
        try? fh.close()
        return true
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
