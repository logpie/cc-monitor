import Foundation
import CCMonitorCore

var passed = 0
var failed = 0

func check(_ condition: Bool, _ msg: String, file: String = #file, line: Int = #line) {
    if condition { passed += 1 }
    else { failed += 1; print("  FAIL [\(file.split(separator: "/").last ?? ""):\(line)] \(msg)") }
}
func section(_ name: String) { print("--- \(name)") }

// ============================================================
section("Hook: working/compacting → .working")
check(computeStatus(hookState: .working, age: 0, processAlive: true) == .working, "hook=working → working")
check(computeStatus(hookState: .working, age: 600, processAlive: true) == .working, "hook=working old → working")
check(computeStatus(hookState: .compacting, age: 30, processAlive: true) == .working, "hook=compacting → working")

section("Hook: idle → .idle")
check(computeStatus(hookState: .idle, age: 0, processAlive: true) == .idle, "hook=idle → idle")
check(computeStatus(hookState: .idle, age: 600, processAlive: true) == .idle, "hook=idle old → idle")

section("Hook: waiting_permission/waiting_input → .attention")
check(computeStatus(hookState: .waitingPermission, age: 10, processAlive: true) == .attention, "hook=waitingPermission → attention")
check(computeStatus(hookState: .waitingInput, age: 10, processAlive: true) == .attention, "hook=waitingInput → attention")

section("Hook: dead process overrides hook → .disconnected")
check(computeStatus(hookState: .working, age: 60, processAlive: false) == .disconnected, "hook=working but dead → disconnected")
check(computeStatus(hookState: .idle, age: 60, processAlive: false) == .disconnected, "hook=idle but dead → disconnected")
check(computeStatus(hookState: .waitingPermission, age: 60, processAlive: false) == .disconnected, "hook=attention but dead → disconnected")

section("Hook: recent dead still uses hook (liveness not checked yet)")
check(computeStatus(hookState: .working, age: 2, processAlive: false) == .working, "hook=working age=2 dead → working")

// ============================================================
section("Fallback (no hook): recent → working")
check(computeStatus(age: 0, processAlive: true) == .working, "no hook age=0 → working")
check(computeStatus(age: 3, processAlive: true) == .working, "no hook age=3 → working")
check(computeStatus(age: 3.001, processAlive: true) == .idle, "no hook age=3.001 → idle")

section("Fallback: older alive → idle")
check(computeStatus(age: 16, processAlive: true) == .idle, "no hook age=16 → idle")
check(computeStatus(age: 600, processAlive: true) == .idle, "no hook age=600 → idle")

section("Fallback: older dead → disconnected")
check(computeStatus(age: 16, processAlive: false) == .disconnected, "no hook age=16 dead → disconnected")

// ============================================================
section("sessionAction: alive never deleted")
for age in [0.0, 60, 600, 86400] as [TimeInterval] {
    let action = sessionAction(hookState: .working, age: age, processAlive: true)
    if case .delete = action { check(false, "alive age=\(age) deleted") }
    else { check(true, "alive age=\(age) kept") }
}

section("sessionAction: dead old → delete")
if case .delete = sessionAction(hookState: .idle, age: 301, processAlive: false) {
    check(true, "dead age=301 → deleted")
} else { check(false, "dead age=301 should delete") }

// ============================================================
section("HookState parsing")
check(HookState(rawValue: "working") == .working, "'working'")
check(HookState(rawValue: "idle") == .idle, "'idle'")
check(HookState(rawValue: "waiting_permission") == .waitingPermission, "'waiting_permission'")
check(HookState(rawValue: "waiting_input") == .waitingInput, "'waiting_input'")
check(HookState(rawValue: "compacting") == .compacting, "'compacting'")
check(HookState(rawValue: "garbage") == nil, "'garbage' → nil")

// ============================================================
section("Grouping: all 4 statuses")
do {
    var sessions = [SessionInfo]()
    let now = Date().timeIntervalSince1970
    let statuses: [AgentStatus] = [.attention, .working, .idle, .disconnected]

    for (i, s) in statuses.enumerated() {
        let json = """
        {"session_id":"s\(i)","project_name":"p\(i)","git_branch":"","model":"O",
         "context_used_pct":30,"context_window_size":200000,"cost_usd":\(Double(i)),
         "last_updated":\(now),"tty":"","tmux_target":"","tmux_window_name":"",
         "tab_title":"","ghostty_window":"","ghostty_tab":""}
        """
        var session = try JSONDecoder().decode(SessionInfo.self, from: json.data(using: .utf8)!)
        session.cachedStatus = s
        sessions.append(session)
    }

    let grouped = Dictionary(grouping: sessions) { $0.cachedStatus }
    let groups = AgentStatus.displayOrder.compactMap { status -> (AgentStatus, [SessionInfo])? in
        guard let s = grouped[status], !s.isEmpty else { return nil }
        return (status, s)
    }
    check(groups.count == 4, "4 groups")
    for (status, items) in groups {
        for s in items { check(s.cachedStatus == status, "\(s.sessionId) in correct group") }
    }
}

// ============================================================
section("Display order: attention first")
let order = AgentStatus.displayOrder
check(order[0] == .attention, "attention first")
check(order[1] == .working, "working second")
check(order[2] == .idle, "idle third")
check(order[3] == .disconnected, "disconnected last")

// ============================================================
section("Relative time formatting")
check(formatRelativeTime(0) == "just now", "age=0 → just now")
check(formatRelativeTime(5) == "just now", "age=5 → just now")
check(formatRelativeTime(9.9) == "just now", "age=9.9 → just now")
check(formatRelativeTime(10) == "10s", "age=10 → 10s")
check(formatRelativeTime(45) == "45s", "age=45 → 45s")
check(formatRelativeTime(59) == "59s", "age=59 → 59s")
check(formatRelativeTime(60) == "1m", "age=60 → 1m")
check(formatRelativeTime(150) == "2m", "age=150 → 2m")
check(formatRelativeTime(3599) == "59m", "age=3599 → 59m")
check(formatRelativeTime(3600) == "1h", "age=3600 → 1h")
check(formatRelativeTime(7200) == "2h", "age=7200 → 2h")
check(formatRelativeTime(86400) == "1d", "age=86400 → 1d")

// ============================================================
section("JSON state file parsing")
do {
    // JSON with context
    let r1 = parseHookStateFile(#"{"state":"working","context":"Edit file.swift"}"#)
    check(r1.state == .working, "JSON working state")
    check(r1.context == "Edit file.swift", "JSON context extracted")
    check(r1.lastMessage == nil, "no last_message")

    // JSON without context
    let r2 = parseHookStateFile(#"{"state":"idle","context":""}"#)
    check(r2.state == .idle, "JSON idle state")
    check(r2.context == nil, "empty context → nil")

    // JSON with no context key
    let r3 = parseHookStateFile(#"{"state":"compacting"}"#)
    check(r3.state == .compacting, "JSON compacting state")
    check(r3.context == nil, "missing context → nil")

    // Plain text fallback
    let r4 = parseHookStateFile("working\n")
    check(r4.state == .working, "plain text working")
    check(r4.context == nil, "plain text no context")

    // Plain text unknown
    let r5 = parseHookStateFile("garbage")
    check(r5.state == nil, "plain text garbage → nil")
    check(r5.context == nil, "plain text garbage no context")

    // JSON waiting_permission with context
    let r6 = parseHookStateFile(#"{"state":"waiting_permission","context":"$ rm -rf /"}"#)
    check(r6.state == .waitingPermission, "JSON waiting_permission")
    check(r6.context == "$ rm -rf /", "JSON permission context")

    // JSON with last_message
    let r7 = parseHookStateFile(#"{"state":"idle","context":"Edit foo.swift","last_message":"Done. Committed as abc123."}"#)
    check(r7.state == .idle, "JSON idle with message")
    check(r7.context == "Edit foo.swift", "context preserved")
    check(r7.lastMessage == "Done. Committed as abc123.", "last_message extracted")

    // JSON with empty last_message
    let r8 = parseHookStateFile(#"{"state":"working","context":"","last_message":""}"#)
    check(r8.lastMessage == nil, "empty last_message → nil")
}

// ============================================================
print("")
if failed == 0 { print("All \(passed) tests passed.") }
else { print("\(failed) FAILED, \(passed) passed."); exit(1) }
