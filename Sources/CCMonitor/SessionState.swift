import Foundation

enum AgentStatus: String, Codable {
    case working
    case waiting
    case idle
    case error
}

struct SessionInfo: Identifiable, Codable {
    let sessionId: String
    let projectName: String
    let gitBranch: String
    let model: String
    let contextUsedPct: Double
    let contextWindowSize: Int
    let costUsd: Double
    let lastUpdated: TimeInterval
    let tty: String?
    let tmuxTarget: String?

    var id: String { sessionId }

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
    }

    /// Derive status from how recently the file was updated
    func status(now: Date = Date()) -> AgentStatus {
        let age = now.timeIntervalSince1970 - lastUpdated
        if age > 120 { return .error }
        if age > 30  { return .idle }
        if age > 5   { return .waiting }
        return .working
    }

    /// Context bar color tier
    var contextTier: ContextTier {
        if contextUsedPct >= 85 { return .critical }
        if contextUsedPct >= 60 { return .warning }
        return .healthy
    }
}

enum ContextTier {
    case healthy, warning, critical
}
