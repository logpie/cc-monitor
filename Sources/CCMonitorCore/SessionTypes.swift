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
    public let gitBranch: String
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
        if let t = tabTitle, !t.isEmpty { return t }
        if let w = tmuxWindowName, !w.isEmpty { return w }
        return projectName
    }

    public var displaySubtitle: String {
        return projectName
    }

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case projectName = "project_name"
        case gitBranch = "git_branch"
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
