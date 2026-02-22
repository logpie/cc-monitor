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

/// Thinking/silence threshold: when NO streaming has occurred since the last hook event
/// (reporter NOT fresher than hook), the model may be thinking or the session may be idle.
/// These two states are fundamentally indistinguishable from the outside.
/// 12s balances quick idle detection vs brief false-idle during extended thinking.
/// (Extended thinks can be 30-120s for Opus, but false idle during thinking is cosmetic
/// — the user isn't looking at the menu bar while waiting for thinking to complete.)
public let thinkingStaleThresholdSeconds: TimeInterval = 12

/// Streaming fast-path threshold: when the reporter WAS actively updating (streaming) but then
/// stopped, detect idle sooner. Only applies when reporter updated more recently than
/// the hook file (proving streaming occurred after the last tool/event).
/// Trade-off: during 7s reporter gaps, age may briefly exceed 6 causing ~0.5s false idle.
/// Reporter fires every 3-7s, so age typically peaks at 5-7. Strict > keeps age=6 safe.
public let streamStopStaleSeconds: TimeInterval = 6

/// Compute status from hook state (preferred) or fall back to time-based.
/// - hookAge: seconds since hook state file was last modified
/// - age: seconds since last_updated field in JSON (used for time-based fallback and liveness)
public func computeStatus(hookState: HookState?, hookAge: TimeInterval? = nil, age: TimeInterval, processAlive: Bool, hasActiveAgents: Bool = false) -> AgentStatus {
    // If process is dead, always disconnected
    if !processAlive && age > livenessCheckThresholdSeconds {
        return .disconnected
    }

    // If we have a hook state, use it directly
    if let hook = hookState {
        switch hook {
        case .compacting:
            return .working
        case .working:
            if let hookAge = hookAge {
                // Was the reporter updating AFTER the last hook event?
                // hookAge > age + 2 requires reporter fired ≥2s after hook,
                // proving sustained streaming (not just a single coincidental fire).
                let reporterFresherThanHook = hookAge > age + 2.0

                if reporterFresherThanHook {
                    // Streaming was proven active. If reporter goes stale,
                    // streaming stopped (user pressed Escape or response ended).
                    if age > streamStopStaleSeconds {
                        return processAlive ? .idle : .disconnected
                    }
                } else if !hasActiveAgents {
                    // No streaming since last hook → likely thinking phase.
                    // During extended thinking, neither hooks nor reporter fire,
                    // so both ages grow together.
                    // Skip this fallback when subagents are known to be running —
                    // their presence proves the session is actively working.
                    if hookAge > thinkingStaleThresholdSeconds,
                       age > thinkingStaleThresholdSeconds {
                        return processAlive ? .idle : .disconnected
                    }
                }
            }
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

public func sessionAction(hookState: HookState?, hookAge: TimeInterval? = nil, age: TimeInterval, processAlive: Bool, hasActiveAgents: Bool = false) -> SessionAction {
    if !processAlive && age > deadCleanupThresholdSeconds {
        return .delete
    }
    return .keep(computeStatus(hookState: hookState, hookAge: hookAge, age: age, processAlive: processAlive, hasActiveAgents: hasActiveAgents))
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

/// A subagent currently running within a session.
public struct ActiveAgent {
    public let id: String
    public let type: String

    public init(id: String, type: String) {
        self.id = id
        self.type = type
    }
}

/// Parsed hook state file result.
public struct HookFileData {
    public let state: HookState?
    public let context: String?
    public let lastMessage: String?
    public let activeAgents: [ActiveAgent]

    public init(state: HookState?, context: String?, lastMessage: String?, activeAgents: [ActiveAgent] = []) {
        self.state = state
        self.context = context
        self.lastMessage = lastMessage
        self.activeAgents = activeAgents
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

        var agents: [ActiveAgent] = []
        if let agentsArray = json["agents"] as? [[String: Any]] {
            for entry in agentsArray {
                if let id = entry["id"] as? String, let type = entry["type"] as? String {
                    agents.append(ActiveAgent(id: id, type: type))
                }
            }
        }

        return HookFileData(state: state, context: cleanContext, lastMessage: cleanMessage, activeAgents: agents)
    }

    // Fallback: plain text (backward compat)
    return HookFileData(state: HookState(rawValue: trimmed), context: nil, lastMessage: nil)
}
