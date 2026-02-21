import Foundation

public enum AgentStatus: String, Codable, Hashable {
    case attention      // waiting for permission or user input
    case working        // actively processing or compacting
    case idle           // finished turn, waiting for next prompt
    case disconnected   // process dead

    /// Display order: attention first (needs action), then working, idle, disconnected
    public static var displayOrder: [AgentStatus] { [.attention, .working, .idle, .disconnected] }

    /// Fallback display label when no hook state is available
    public var displayLabel: String {
        switch self {
        case .attention:    return "Needs Input"
        case .working:      return "Working"
        case .idle:         return "Ready"
        case .disconnected: return "Disconnected"
        }
    }
}

public struct SessionInfo: Identifiable, Codable {
    public let sessionId: String
    public let projectName: String
    public var projectDir: String?
    public let gitBranch: String
    public var gitDirty: Int?
    public var gitStaged: Int?
    public var gitUntracked: Int?
    public let model: String
    public let contextUsedPct: Double
    public let contextWindowSize: Int
    public let costUsd: Double
    public let lastUpdated: TimeInterval
    public let tty: String?
    public let tmuxTarget: String?
    public let tmuxWindowName: String?
    public let tabTitle: String?
    public let ghosttyWindow: String?
    public let ghosttyTab: String?

    public var id: String { sessionId }

    public var displayLabel: String {
        if let t = ghosttyTabTitle, !t.isEmpty { return t }
        if let t = tabTitle, !t.isEmpty { return t }
        if let w = tmuxWindowName, !w.isEmpty { return w }
        return projectName
    }

    /// Git status summary (e.g. "+3 ~2 ?1")
    public var gitStatusSummary: String? {
        let s = gitStaged ?? 0
        let d = gitDirty ?? 0
        let u = gitUntracked ?? 0
        if s == 0 && d == 0 && u == 0 { return nil }
        var parts: [String] = []
        if s > 0 { parts.append("+\(s)") }
        if d > 0 { parts.append("~\(d)") }
        if u > 0 { parts.append("?\(u)") }
        return parts.joined(separator: " ")
    }

    /// Shortened path for disambiguation (e.g. "~/work/cc-monitor")
    public var displayPath: String {
        guard let dir = projectDir, !dir.isEmpty else { return projectName }
        let home = NSHomeDirectory()
        if dir.hasPrefix(home) {
            return "~" + dir.dropFirst(home.count)
        }
        return dir
    }

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case projectName = "project_name"
        case projectDir = "project_dir"
        case gitBranch = "git_branch"
        case gitDirty = "git_dirty"
        case gitStaged = "git_staged"
        case gitUntracked = "git_untracked"
        case model
        case contextUsedPct = "context_used_pct"
        case contextWindowSize = "context_window_size"
        case costUsd = "cost_usd"
        case lastUpdated = "last_updated"
        case tty
        case tmuxTarget = "tmux_target"
        case tmuxWindowName = "tmux_window_name"
        case tabTitle = "tab_title"
        case ghosttyWindow = "ghostty_window"
        case ghosttyTab = "ghostty_tab"
    }

    /// Whether the claude process is still alive on the TTY (set by SessionMonitor)
    public var processAlive: Bool = true

    /// Cached status computed once by SessionMonitor.loadSessions()
    public var cachedStatus: AgentStatus = .idle

    /// Raw hook state for detailed display text
    public var hookState: HookState?

    /// Task context from hook (e.g. "Edit StatusDot.swift", "$ npm test")
    public var hookContext: String?

    /// Last assistant message (first line, truncated)
    public var lastMessage: String?

    /// Active subagents running in this session
    public var activeAgents: [ActiveAgent] = []

    /// Ghostty tab title resolved via AppleScript
    public var ghosttyTabTitle: String?

    /// Specific status text based on actual hook state
    public var detailedStatusText: String {
        if let hook = hookState {
            switch hook {
            case .working:           return "Working"
            case .compacting:        return "Compacting"
            case .waitingPermission: return "Waiting for Permission"
            case .waitingInput:      return "Waiting for Input"
            case .idle:              return "Ready"
            }
        }
        return cachedStatus.displayLabel
    }

    /// Relative time since last update (e.g. "just now", "2m", "1h")
    public var relativeTime: String {
        let age = Date().timeIntervalSince1970 - lastUpdated
        return formatRelativeTime(age)
    }

    public var contextTier: ContextTier {
        if contextUsedPct >= 85 { return .critical }
        if contextUsedPct >= 60 { return .warning }
        return .healthy
    }
}

public enum ContextTier {
    case healthy, warning, critical
}
