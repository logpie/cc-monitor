import Foundation
import Combine

@MainActor
final class SessionMonitor: ObservableObject {
    @Published var sessions: [SessionInfo] = []

    private let monitorDir: URL
    private var dirSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var refreshTimer: Timer?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.monitorDir = home.appendingPathComponent(".claude/monitor")

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: monitorDir, withIntermediateDirectories: true)

        startWatching()
        startPeriodicRefresh()
        loadSessions()
    }

    deinit {
        dirSource?.cancel()
        if fileDescriptor >= 0 { Darwin.close(fileDescriptor) }
        refreshTimer?.invalidate()
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
            self?.loadSessions()
        }
        source.setCancelHandler { [fd = fileDescriptor] in
            Darwin.close(fd)
        }
        source.resume()
        self.dirSource = source
    }

    /// Periodic refresh to update derived status (age-based)
    private func startPeriodicRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.loadSessions()
            }
        }
    }

    func loadSessions() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: monitorDir,
            includingPropertiesForKeys: nil
        ) else { return }

        let now = Date()
        sessions = files
            .filter { $0.pathExtension == "json" && !$0.lastPathComponent.hasPrefix(".") }
            .compactMap { url -> SessionInfo? in
                guard let data = try? Data(contentsOf: url),
                      let session = try? JSONDecoder().decode(SessionInfo.self, from: data)
                else { return nil }

                // Remove files stale beyond 5 minutes (session is long gone)
                let age = now.timeIntervalSince1970 - session.lastUpdated
                if age > 300 {
                    try? FileManager.default.removeItem(at: url)
                    return nil
                }
                return session
            }
            .sorted { $0.projectName < $1.projectName }
    }
}
