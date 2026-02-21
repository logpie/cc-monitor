import Foundation

/// Fallback working threshold (only used when hook state is unavailable).
public let workingThresholdSeconds: TimeInterval = 3

/// Seconds after last report before we check process liveness.
public let livenessCheckThresholdSeconds: TimeInterval = 5

/// Seconds after which dead sessions' files are cleaned up.
public let deadCleanupThresholdSeconds: TimeInterval = 300

/// Hook states written by monitor-hook.sh
public enum HookState: String {
    case working
    case idle
    case waitingPermission = "waiting_permission"
    case waitingInput = "waiting_input"
    case compacting
}

/// Compute status from hook state (preferred) or fall back to time-based.
public func computeStatus(hookState: HookState?, age: TimeInterval, processAlive: Bool) -> AgentStatus {
    // If process is dead, always disconnected
    if !processAlive && age > livenessCheckThresholdSeconds {
        return .disconnected
    }

    // If we have a hook state, use it directly
    if let hook = hookState {
        switch hook {
        case .working, .compacting:
            return .working
        case .waitingPermission, .waitingInput:
            return .attention
        case .idle:
            return .idle
        }
    }

    // Fallback: time-based (for sessions without hooks)
    if age <= workingThresholdSeconds { return .working }
    if processAlive { return .idle }
    return .disconnected
}

/// Legacy: compute without hook state (for tests and fallback).
public func computeStatus(age: TimeInterval, processAlive: Bool) -> AgentStatus {
    return computeStatus(hookState: nil, age: age, processAlive: processAlive)
}

/// Determine what action to take for a session file given its age and liveness.
public enum SessionAction {
    case keep(AgentStatus)
    case delete
}

public func sessionAction(hookState: HookState?, age: TimeInterval, processAlive: Bool) -> SessionAction {
    if !processAlive && age > deadCleanupThresholdSeconds {
        return .delete
    }
    return .keep(computeStatus(hookState: hookState, age: age, processAlive: processAlive))
}

public func sessionAction(age: TimeInterval, processAlive: Bool) -> SessionAction {
    return sessionAction(hookState: nil, age: age, processAlive: processAlive)
}

/// Whether liveness should be checked for the given age.
public func shouldCheckLiveness(age: TimeInterval) -> Bool {
    return age > livenessCheckThresholdSeconds
}

/// Format age as relative time string (pure function for testing).
public func formatRelativeTime(_ age: TimeInterval) -> String {
    if age < 10 { return "just now" }
    if age < 60 { return "\(Int(age))s" }
    if age < 3600 { return "\(Int(age / 60))m" }
    if age < 86400 { return "\(Int(age / 3600))h" }
    return "\(Int(age / 86400))d"
}

/// Parsed hook state file result.
public struct HookFileData {
    public let state: HookState?
    public let context: String?
    public let lastMessage: String?

    public init(state: HookState?, context: String?, lastMessage: String?) {
        self.state = state
        self.context = context
        self.lastMessage = lastMessage
    }
}

/// Parse a hook state file (JSON or plain text fallback).
public func parseHookStateFile(_ content: String) -> HookFileData {
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

    // Try JSON format first
    if trimmed.hasPrefix("{"),
       let data = trimmed.data(using: .utf8),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let stateStr = json["state"] as? String {
        let state = HookState(rawValue: stateStr)
        let context = json["context"] as? String
        let cleanContext = (context?.isEmpty == true) ? nil : context
        let message = json["last_message"] as? String
        let cleanMessage = (message?.isEmpty == true) ? nil : message
        return HookFileData(state: state, context: cleanContext, lastMessage: cleanMessage)
    }

    // Fallback: plain text (backward compat)
    return HookFileData(state: HookState(rawValue: trimmed), context: nil, lastMessage: nil)
}
