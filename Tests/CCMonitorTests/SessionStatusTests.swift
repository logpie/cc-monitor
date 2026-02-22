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
// MARK: - Event-replay simulation
// ============================================================
// Models real Claude Code behavior: hook events write the .state file,
// the statusLine reporter writes the .json file. SessionMonitor polls
// and calls computeStatus() with the file states.
//
// Real event sources (from ~/.claude/settings.json):
//   SessionStart     → hook(idle)
//   UserPromptSubmit → hook(working)
//   PreToolUse       → hook(working)
//   Stop             → hook(idle)         [does NOT fire on user interrupt!]
//   PermissionRequest→ hook(waiting_permission)
//   Notification(permission_prompt) → hook(waiting_permission)
//   Notification(idle_prompt) → hook(idle) [fires when idle prompt appears, including after interrupt]
//   PreCompact       → hook(compacting)
//   SubagentStart    → hook(working) + agents updated
//   SubagentStop     → hook(working) + agents updated
//   statusLine       → reporter writes JSON only (no hook state change)

enum SimEventKind {
    case hook(HookState)
    case statusLine      // reporter writes JSON only
    case crash           // process dies
}

struct SimEvent {
    let time: TimeInterval
    let kind: SimEventKind
}

/// Replay events up to time T and compute status.
func statusAt(_ t: TimeInterval, events: [SimEvent]) -> AgentStatus {
    var hookState: HookState? = nil
    var hookWriteTime: TimeInterval? = nil
    var jsonWriteTime: TimeInterval? = nil
    var alive = true

    for e in events {
        guard e.time <= t else { break }
        switch e.kind {
        case .hook(let state):
            hookState = state
            hookWriteTime = e.time
            jsonWriteTime = e.time    // reporter also fires on hook events
        case .statusLine:
            jsonWriteTime = e.time
        case .crash:
            alive = false
        }
    }

    guard let jt = jsonWriteTime else { return .idle }
    let hookAge: TimeInterval? = hookWriteTime.map { t - $0 }
    let age = t - jt
    return computeStatus(hookState: hookState, hookAge: hookAge, age: age, processAlive: alive)
}

func actionAt(_ t: TimeInterval, events: [SimEvent]) -> SessionAction {
    var hookState: HookState? = nil
    var hookWriteTime: TimeInterval? = nil
    var jsonWriteTime: TimeInterval? = nil
    var alive = true

    for e in events {
        guard e.time <= t else { break }
        switch e.kind {
        case .hook(let state):
            hookState = state
            hookWriteTime = e.time
            jsonWriteTime = e.time
        case .statusLine:
            jsonWriteTime = e.time
        case .crash:
            alive = false
        }
    }

    guard let jt = jsonWriteTime else { return .keep(.idle) }
    let hookAge: TimeInterval? = hookWriteTime.map { t - $0 }
    let age = t - jt
    return sessionAction(hookState: hookState, hookAge: hookAge, age: age, processAlive: alive)
}

struct Expect {
    let t: TimeInterval
    let status: AgentStatus
    let reason: String
}

func verify(_ events: [SimEvent], _ expectations: [Expect], label: String) {
    for e in expectations {
        let actual = statusAt(e.t, events: events)
        check(actual == e.status,
              "\(label) T=\(Int(e.t))s: expected \(e.status) got \(actual) — \(e.reason)")
    }
}

// ============================================================
// MARK: - FALSE POSITIVE TESTS
// These test that sessions which ARE working never show idle.
// ============================================================

section("FP1: Normal work with streaming between tools — must NEVER show idle")
do {
    // Claude runs tools with varied think gaps. Between tools, Claude is streaming
    // text so the reporter fires every ~5s, keeping age < 8.
    let events: [SimEvent] = [
        SimEvent(time: 0,  kind: .hook(.idle)),
        SimEvent(time: 1,  kind: .hook(.working)),      // UserPromptSubmit
        SimEvent(time: 3,  kind: .hook(.working)),      // PreToolUse (tool 1)
        SimEvent(time: 4,  kind: .statusLine),
        SimEvent(time: 9,  kind: .statusLine),           // streaming between tools
        // 10s gap — hookAge approaches threshold, reporter keeps age fresh
        SimEvent(time: 13, kind: .hook(.working)),      // PreToolUse (tool 2)
        SimEvent(time: 14, kind: .statusLine),
        SimEvent(time: 19, kind: .statusLine),
        SimEvent(time: 24, kind: .statusLine),
        // 15s gap with streaming
        SimEvent(time: 28, kind: .hook(.working)),      // PreToolUse (tool 3)
        SimEvent(time: 29, kind: .statusLine),
        SimEvent(time: 34, kind: .statusLine),
        SimEvent(time: 39, kind: .statusLine),
        SimEvent(time: 44, kind: .statusLine),
        // 20s gap with streaming
        SimEvent(time: 48, kind: .hook(.working)),      // PreToolUse (tool 4)
        SimEvent(time: 49, kind: .statusLine),
        SimEvent(time: 54, kind: .statusLine),
        SimEvent(time: 59, kind: .statusLine),
        SimEvent(time: 64, kind: .statusLine),
        SimEvent(time: 69, kind: .statusLine),
        // 25s gap with streaming
        SimEvent(time: 73, kind: .hook(.working)),      // PreToolUse (tool 5)
        SimEvent(time: 76, kind: .hook(.idle)),          // Stop
    ]

    // Check every second during work phase — must ALWAYS be working
    for t in stride(from: 1.0, through: 75.0, by: 1.0) {
        let s = statusAt(t, events: events)
        check(s == .working, "FP1 T=\(Int(t))s: must be working (got \(s))")
    }
    check(statusAt(76, events: events) == .idle, "FP1 T=76: done")
}

section("FP2: Long response streaming — must NOT show idle during active stream")
do {
    // Claude runs tool at T=5, then streams a long response for 45 seconds.
    // Reporter fires periodically during streaming (~every 5s).
    // hookAge grows past 10 but reporter proves session is still active.
    let events: [SimEvent] = [
        SimEvent(time: 0,  kind: .hook(.idle)),
        SimEvent(time: 2,  kind: .hook(.working)),      // UserPromptSubmit
        SimEvent(time: 5,  kind: .hook(.working)),      // PreToolUse (last tool)
        // 45 seconds of response streaming with periodic reporter updates
        SimEvent(time: 8,  kind: .statusLine),
        SimEvent(time: 13, kind: .statusLine),           // hookAge=8
        SimEvent(time: 18, kind: .statusLine),           // hookAge=13 (past 10!)
        SimEvent(time: 23, kind: .statusLine),           // hookAge=18
        SimEvent(time: 28, kind: .statusLine),           // hookAge=23
        SimEvent(time: 33, kind: .statusLine),           // hookAge=28
        SimEvent(time: 38, kind: .statusLine),           // hookAge=33
        SimEvent(time: 43, kind: .statusLine),           // hookAge=38
        SimEvent(time: 48, kind: .statusLine),           // hookAge=43
        SimEvent(time: 50, kind: .hook(.idle)),          // Stop (response done)
    ]

    // During streaming (T=5 to T=49): hookAge exceeds 10 after T=15,
    // but reporter proves session is active (age < 8). Must NOT show idle.
    for t in stride(from: 5.0, through: 49.0, by: 1.0) {
        let s = statusAt(t, events: events)
        check(s == .working, "FP2 T=\(Int(t))s: streaming, must be working (got \(s))")
    }
    check(statusAt(50, events: events) == .idle, "FP2 T=50: response done → idle")
}

section("FP3: Long tool execution (e.g. slow Bash command)")
do {
    // User runs a Bash command that takes 60s. PreToolUse fires at start.
    // Reporter fires periodically during execution (~every 7s).
    let events: [SimEvent] = [
        SimEvent(time: 0,  kind: .hook(.idle)),
        SimEvent(time: 2,  kind: .hook(.working)),      // UserPromptSubmit
        SimEvent(time: 4,  kind: .hook(.working)),      // PreToolUse(Bash) — tool starts
        // Tool runs for 60 seconds, reporter updates periodically
        SimEvent(time: 11, kind: .statusLine),
        SimEvent(time: 18, kind: .statusLine),
        SimEvent(time: 25, kind: .statusLine),
        SimEvent(time: 32, kind: .statusLine),
        SimEvent(time: 39, kind: .statusLine),
        SimEvent(time: 46, kind: .statusLine),
        SimEvent(time: 53, kind: .statusLine),
        SimEvent(time: 60, kind: .statusLine),
        // Tool finishes, Claude continues
        SimEvent(time: 64, kind: .hook(.working)),      // Next PreToolUse
        SimEvent(time: 68, kind: .hook(.idle)),          // Stop
    ]

    // During entire tool execution: must stay working
    for t in stride(from: 4.0, through: 63.0, by: 2.0) {
        let s = statusAt(t, events: events)
        check(s == .working, "FP3 T=\(Int(t))s: tool running, must be working (got \(s))")
    }
}

section("FP4: Compacting — immune to staleness at any duration")
do {
    let events: [SimEvent] = [
        SimEvent(time: 0,  kind: .hook(.idle)),
        SimEvent(time: 2,  kind: .hook(.working)),
        SimEvent(time: 5,  kind: .hook(.compacting)),   // PreCompact
        // 3 minutes of compacting, no hooks
        SimEvent(time: 185, kind: .hook(.idle)),         // SessionStart(compact)
    ]

    for t in stride(from: 5.0, through: 184.0, by: 10.0) {
        let s = statusAt(t, events: events)
        check(s == .working, "FP4 T=\(Int(t))s: compacting, must be working (got \(s))")
    }
    check(statusAt(185, events: events) == .idle, "FP4 T=185: compacting done")
}

section("FP5: Permission/input wait — immune to staleness at any duration")
do {
    let events: [SimEvent] = [
        SimEvent(time: 0,   kind: .hook(.idle)),
        SimEvent(time: 2,   kind: .hook(.working)),
        SimEvent(time: 4,   kind: .hook(.waitingPermission)),
    ]

    // Must stay attention for 10 full minutes
    for t in stride(from: 4.0, through: 600.0, by: 30.0) {
        let s = statusAt(t, events: events)
        check(s == .attention, "FP5 T=\(Int(t))s: waiting permission, must be attention (got \(s))")
    }
}

section("FP6: Subagent running with reporter — must not show idle")
do {
    // Subagent runs for 25s. Reporter fires during execution (~every 5s).
    let events: [SimEvent] = [
        SimEvent(time: 0,  kind: .hook(.idle)),
        SimEvent(time: 2,  kind: .hook(.working)),
        SimEvent(time: 4,  kind: .hook(.working)),      // PreToolUse(Task)
        SimEvent(time: 5,  kind: .hook(.working)),      // SubagentStart
        SimEvent(time: 10, kind: .statusLine),
        SimEvent(time: 15, kind: .statusLine),
        SimEvent(time: 20, kind: .statusLine),
        SimEvent(time: 25, kind: .statusLine),
        SimEvent(time: 30, kind: .hook(.working)),      // SubagentStop
        SimEvent(time: 35, kind: .hook(.idle)),          // Stop
    ]

    for t in stride(from: 5.0, through: 29.0, by: 1.0) {
        let s = statusAt(t, events: events)
        check(s == .working, "FP6 T=\(Int(t))s: subagent running, must be working (got \(s))")
    }
}

section("FP7: Reporter fires every 7s (worst case) — must NOT false-idle")
do {
    // Stress test: reporter fires at exactly 7s intervals (max observed gap).
    // hookAge grows past 10, but age peaks at 7 < 8.
    let events: [SimEvent] = [
        SimEvent(time: 0,  kind: .hook(.idle)),
        SimEvent(time: 2,  kind: .hook(.working)),      // UserPromptSubmit
        SimEvent(time: 3,  kind: .hook(.working)),      // PreToolUse
        SimEvent(time: 4,  kind: .statusLine),
        // No more hooks. Reporter fires every 7s.
        SimEvent(time: 11, kind: .statusLine),
        SimEvent(time: 18, kind: .statusLine),
        SimEvent(time: 25, kind: .statusLine),
        SimEvent(time: 32, kind: .statusLine),
        SimEvent(time: 39, kind: .statusLine),
        SimEvent(time: 46, kind: .statusLine),
        SimEvent(time: 50, kind: .hook(.idle)),          // Stop
    ]

    // hookAge exceeds 10 after T=13, but age always < 7 (reporter fires every 7s).
    // At worst: T=18-epsilon, age=7-epsilon < 8. Must stay working.
    for t in stride(from: 3.0, through: 49.0, by: 1.0) {
        let s = statusAt(t, events: events)
        check(s == .working, "FP7 T=\(Int(t))s: worst-case reporter gap, must be working (got \(s))")
    }
}

// ============================================================
// MARK: - LAGGY BEHAVIOR TESTS
// These test that state transitions are prompt, not delayed.
// ============================================================

section("LAG1: Hook transitions are immediate (0-latency)")
do {
    let events: [SimEvent] = [
        SimEvent(time: 0,  kind: .hook(.idle)),          // SessionStart
        SimEvent(time: 10, kind: .hook(.working)),        // UserPromptSubmit
        SimEvent(time: 20, kind: .hook(.waitingPermission)),
        SimEvent(time: 30, kind: .hook(.working)),        // user approves
        SimEvent(time: 40, kind: .hook(.idle)),            // Stop
    ]

    check(statusAt(0,  events: events) == .idle,      "LAG1 T=0: SessionStart → idle (instant)")
    check(statusAt(10, events: events) == .working,   "LAG1 T=10: UserPrompt → working (instant)")
    check(statusAt(20, events: events) == .attention,  "LAG1 T=20: Permission → attention (instant)")
    check(statusAt(30, events: events) == .working,   "LAG1 T=30: Approved → working (instant)")
    check(statusAt(40, events: events) == .idle,      "LAG1 T=40: Stop → idle (instant)")
}

section("LAG2: Broken Stop hook — detect idle within threshold + response time")
do {
    // Last tool at T=5, response streams until T=15, then session finishes.
    // Stop FAILS. Last reporter at T=14 (during streaming).
    let events: [SimEvent] = [
        SimEvent(time: 0,  kind: .hook(.idle)),
        SimEvent(time: 2,  kind: .hook(.working)),
        SimEvent(time: 5,  kind: .hook(.working)),      // last PreToolUse
        SimEvent(time: 8,  kind: .statusLine),
        SimEvent(time: 11, kind: .statusLine),
        SimEvent(time: 14, kind: .statusLine),           // last reporter
        // T=15: session finishes, Stop FAILS, no more events
    ]

    // hookAge > 10 at T=16 (from T=5). age > 8 at T=23 (from T=14).
    // Detection at max(16, 23) = T=23.
    check(statusAt(15, events: events) == .working, "LAG2 T=15: hookAge=10, at threshold")
    check(statusAt(20, events: events) == .working, "LAG2 T=20: hookAge=15, age=6 < 8")
    check(statusAt(22, events: events) == .working, "LAG2 T=22: age=8, at threshold")
    check(statusAt(23, events: events) == .idle,    "LAG2 T=23: stale detected → idle")
}

section("LAG3: Broken Stop, reporter fires late — still detect within reasonable time")
do {
    let events: [SimEvent] = [
        SimEvent(time: 0,  kind: .hook(.idle)),
        SimEvent(time: 2,  kind: .hook(.working)),
        SimEvent(time: 5,  kind: .hook(.working)),      // last PreToolUse
        SimEvent(time: 10, kind: .statusLine),
        SimEvent(time: 15, kind: .statusLine),           // during streaming
        // T=16: session finishes, Stop FAILS
        SimEvent(time: 18, kind: .statusLine),           // late reporter fire after done
        // No more events
    ]

    // hookAge > 10 at T=16. age > 8 at T=27 (from T=18).
    // Detection at max(16, 27) = T=27.
    check(statusAt(22, events: events) == .working, "LAG3 T=22: age=4 (not yet stale)")
    check(statusAt(26, events: events) == .working, "LAG3 T=26: age=8, at threshold")
    check(statusAt(27, events: events) == .idle,    "LAG3 T=27: detected despite late reporter")
}

// ============================================================
// MARK: - SPECIAL STATE TESTS
// ============================================================

section("SP1: User presses Escape — idle_prompt notification fires")
do {
    let events: [SimEvent] = [
        SimEvent(time: 0,  kind: .hook(.idle)),
        SimEvent(time: 2,  kind: .hook(.working)),      // UserPromptSubmit
        SimEvent(time: 5,  kind: .hook(.working)),      // PreToolUse
        SimEvent(time: 8,  kind: .statusLine),           // streaming
        SimEvent(time: 11, kind: .statusLine),           // streaming
        // T=12: User presses Escape. Stop does NOT fire!
        // But Notification(idle_prompt) fires:
        SimEvent(time: 13, kind: .hook(.idle)),           // idle_prompt notification
    ]

    check(statusAt(11, events: events) == .working, "SP1 T=11: streaming")
    check(statusAt(13, events: events) == .idle,    "SP1 T=13: Escape → idle_prompt → idle (instant)")
}

section("SP2: User presses Escape — idle_prompt ALSO fails to fire")
do {
    // Worst case: both Stop and idle_prompt fail.
    let events: [SimEvent] = [
        SimEvent(time: 0,  kind: .hook(.idle)),
        SimEvent(time: 2,  kind: .hook(.working)),
        SimEvent(time: 5,  kind: .hook(.working)),      // last PreToolUse
        SimEvent(time: 8,  kind: .statusLine),
        SimEvent(time: 11, kind: .statusLine),
        // T=12: User presses Escape. NO hooks fire at all.
    ]

    // hookAge > 10 at T=16 (from T=5). age > 8 at T=20 (from T=11).
    // Detection at max(16, 20) = T=20.
    check(statusAt(15, events: events) == .working, "SP2 T=15: hookAge=10, at threshold")
    check(statusAt(19, events: events) == .working, "SP2 T=19: age=8, at threshold")
    check(statusAt(20, events: events) == .idle,    "SP2 T=20: staleness fallback → idle")
}

section("SP3: Ctrl+C kills process")
do {
    let events: [SimEvent] = [
        SimEvent(time: 0,  kind: .hook(.idle)),
        SimEvent(time: 2,  kind: .hook(.working)),
        SimEvent(time: 5,  kind: .hook(.working)),      // PreToolUse
        SimEvent(time: 7,  kind: .statusLine),
        // T=8: Ctrl+C kills process
        SimEvent(time: 8,  kind: .crash),
    ]

    check(statusAt(8,  events: events) == .working,      "SP3 T=8: just crashed, age=1 < 5")
    check(statusAt(13, events: events) == .disconnected,  "SP3 T=13: age=6 > 5, dead → disconnected")

    // After 300s → cleanup
    if case .delete = actionAt(308, events: events) {
        check(true, "SP3 T=308: dead 300s → deleted")
    } else { check(false, "SP3 T=308: should delete") }
}

section("SP4: Compacting then resume")
do {
    let events: [SimEvent] = [
        SimEvent(time: 0,   kind: .hook(.idle)),
        SimEvent(time: 2,   kind: .hook(.working)),
        SimEvent(time: 5,   kind: .hook(.compacting)),    // PreCompact
        SimEvent(time: 125, kind: .hook(.idle)),           // SessionStart(compact)
        SimEvent(time: 126, kind: .hook(.working)),        // PreToolUse (resumed work)
        SimEvent(time: 130, kind: .hook(.idle)),           // Stop
    ]

    check(statusAt(5,   events: events) == .working, "SP4 T=5: compacting starts")
    check(statusAt(60,  events: events) == .working, "SP4 T=60: compacting 55s in")
    check(statusAt(124, events: events) == .working, "SP4 T=124: compacting almost done")
    check(statusAt(125, events: events) == .idle,    "SP4 T=125: SessionStart(compact) → idle")
    check(statusAt(126, events: events) == .working, "SP4 T=126: resumed working")
    check(statusAt(130, events: events) == .idle,    "SP4 T=130: done")
}

section("SP5: Compacting with broken Stop afterwards")
do {
    let events: [SimEvent] = [
        SimEvent(time: 0,   kind: .hook(.idle)),
        SimEvent(time: 5,   kind: .hook(.compacting)),
        SimEvent(time: 125, kind: .hook(.idle)),           // SessionStart(compact)
        SimEvent(time: 126, kind: .hook(.working)),        // UserPromptSubmit (resume)
        SimEvent(time: 128, kind: .hook(.working)),        // PreToolUse (last hook write)
        SimEvent(time: 132, kind: .statusLine),            // streaming
        SimEvent(time: 136, kind: .statusLine),            // last reporter
        // Stop FAILS. hookAge grows from T=128.
    ]

    check(statusAt(128, events: events) == .working, "SP5 T=128: post-compact tool")
    check(statusAt(135, events: events) == .working, "SP5 T=135: hookAge=7, grace period")
    // hookAge > 10 at T=139 (from T=128). age > 8 at T=145 (from T=136).
    // Detection at max(139, 145) = T=145.
    check(statusAt(138, events: events) == .working, "SP5 T=138: hookAge=10 (threshold)")
    check(statusAt(144, events: events) == .working, "SP5 T=144: age=8 (threshold)")
    check(statusAt(145, events: events) == .idle,    "SP5 T=145: hookAge=17, age=9 → idle")
}

section("SP6: Escape during tool execution")
do {
    let events: [SimEvent] = [
        SimEvent(time: 0,  kind: .hook(.idle)),
        SimEvent(time: 2,  kind: .hook(.working)),      // UserPromptSubmit
        SimEvent(time: 4,  kind: .hook(.working)),      // PreToolUse(Bash)
        SimEvent(time: 6,  kind: .statusLine),
        // T=8: Escape, then idle_prompt fires:
        SimEvent(time: 9,  kind: .hook(.idle)),          // idle_prompt
    ]

    check(statusAt(7, events: events) == .working, "SP6 T=7: tool running")
    check(statusAt(9, events: events) == .idle,    "SP6 T=9: Escape → idle_prompt → idle")
}

section("SP7: Escape during tool, idle_prompt also fails")
do {
    let events: [SimEvent] = [
        SimEvent(time: 0,  kind: .hook(.idle)),
        SimEvent(time: 2,  kind: .hook(.working)),
        SimEvent(time: 4,  kind: .hook(.working)),      // PreToolUse(Bash)
        SimEvent(time: 6,  kind: .statusLine),
        // T=8: Escape pressed. NO hooks fire. Reporter stops.
    ]

    // hookAge > 10 at T=15 (from T=4). age > 8 at T=15 (from T=6).
    // Detection at max(15, 15) = T=15.
    check(statusAt(12, events: events) == .working, "SP7 T=12: grace period")
    check(statusAt(14, events: events) == .working, "SP7 T=14: hookAge=10 (threshold), age=8 (threshold)")
    check(statusAt(15, events: events) == .idle,    "SP7 T=15: staleness → idle")
}

section("SP8: Process crash during compacting")
do {
    let events: [SimEvent] = [
        SimEvent(time: 0,  kind: .hook(.idle)),
        SimEvent(time: 2,  kind: .hook(.working)),
        SimEvent(time: 5,  kind: .hook(.compacting)),
        SimEvent(time: 30, kind: .crash),
    ]

    check(statusAt(10, events: events) == .working,      "SP8 T=10: compacting, alive")
    check(statusAt(29, events: events) == .working,      "SP8 T=29: still alive, compacting")
    check(statusAt(36, events: events) == .disconnected,  "SP8 T=36: age=31 > 5, dead → disconnected")
    check(statusAt(60, events: events) == .disconnected,  "SP8 T=60: still dead")
}

// ============================================================
// MARK: - REALISTIC SESSION SIMULATIONS
// ============================================================

section("SIM1: Normal tool workflow, Stop fires correctly")
do {
    let events: [SimEvent] = [
        SimEvent(time: 0,  kind: .hook(.idle)),         // SessionStart
        SimEvent(time: 2,  kind: .hook(.working)),       // UserPromptSubmit
        SimEvent(time: 4,  kind: .hook(.working)),       // PreToolUse(Read)
        SimEvent(time: 5,  kind: .statusLine),
        SimEvent(time: 8,  kind: .hook(.working)),       // PreToolUse(Edit)
        SimEvent(time: 10, kind: .statusLine),
        SimEvent(time: 12, kind: .statusLine),           // streaming
        SimEvent(time: 15, kind: .hook(.idle)),           // Stop
    ]

    verify(events, [
        Expect(t: 0,  status: .idle,    reason: "session started"),
        Expect(t: 2,  status: .working, reason: "prompt submitted"),
        Expect(t: 4,  status: .working, reason: "reading file"),
        Expect(t: 8,  status: .working, reason: "editing file"),
        Expect(t: 12, status: .working, reason: "streaming response"),
        Expect(t: 15, status: .idle,    reason: "Stop fired → idle"),
        Expect(t: 60, status: .idle,    reason: "still idle"),
    ], label: "SIM1")
}

section("SIM2: Multi-turn with permission")
do {
    let events: [SimEvent] = [
        SimEvent(time: 0,   kind: .hook(.idle)),
        SimEvent(time: 5,   kind: .hook(.working)),       // UserPromptSubmit
        SimEvent(time: 7,   kind: .hook(.working)),       // PreToolUse(Read)
        SimEvent(time: 12,  kind: .hook(.working)),       // PreToolUse(Bash)
        SimEvent(time: 13,  kind: .hook(.waitingPermission)), // PermissionRequest
        SimEvent(time: 25,  kind: .hook(.working)),       // user approves
        SimEvent(time: 26,  kind: .hook(.working)),       // PreToolUse (Bash runs)
        SimEvent(time: 28,  kind: .statusLine),
        SimEvent(time: 33,  kind: .hook(.idle)),          // Stop
        SimEvent(time: 60,  kind: .hook(.working)),       // UserPromptSubmit
        SimEvent(time: 62,  kind: .hook(.working)),       // PreToolUse
        SimEvent(time: 65,  kind: .hook(.idle)),          // Stop
    ]

    verify(events, [
        Expect(t: 0,  status: .idle,      reason: "session start"),
        Expect(t: 7,  status: .working,   reason: "turn 1 reading"),
        Expect(t: 13, status: .attention,  reason: "permission needed"),
        Expect(t: 20, status: .attention,  reason: "still waiting"),
        Expect(t: 25, status: .working,    reason: "approved"),
        Expect(t: 33, status: .idle,       reason: "turn 1 done"),
        Expect(t: 50, status: .idle,       reason: "between turns"),
        Expect(t: 60, status: .working,    reason: "turn 2"),
        Expect(t: 65, status: .idle,       reason: "turn 2 done"),
    ], label: "SIM2")
}

section("SIM3: Realistic Opus session — varied think times with streaming")
do {
    // Reporter fires every ~5s during streaming between tools
    let events: [SimEvent] = [
        SimEvent(time: 0,  kind: .hook(.idle)),
        SimEvent(time: 3,  kind: .hook(.working)),       // UserPromptSubmit
        SimEvent(time: 8,  kind: .hook(.working)),       // Tool 1 (5s think)
        SimEvent(time: 9,  kind: .hook(.working)),       // Tool 2 (1s think)
        SimEvent(time: 10, kind: .hook(.working)),       // Tool 3 (1s think)
        SimEvent(time: 11, kind: .statusLine),
        SimEvent(time: 16, kind: .statusLine),           // streaming
        SimEvent(time: 21, kind: .statusLine),
        SimEvent(time: 26, kind: .statusLine),
        // 18s think with streaming
        SimEvent(time: 28, kind: .hook(.working)),       // Tool 4
        SimEvent(time: 29, kind: .statusLine),
        SimEvent(time: 34, kind: .statusLine),
        SimEvent(time: 39, kind: .statusLine),
        // 12s think with streaming
        SimEvent(time: 40, kind: .hook(.working)),       // Tool 5
        SimEvent(time: 42, kind: .statusLine),
        SimEvent(time: 47, kind: .statusLine),
        SimEvent(time: 52, kind: .statusLine),
        SimEvent(time: 57, kind: .statusLine),
        // 22s think with streaming
        SimEvent(time: 62, kind: .hook(.working)),       // Tool 6
        SimEvent(time: 63, kind: .statusLine),
        SimEvent(time: 68, kind: .statusLine),
        // 8s think
        SimEvent(time: 70, kind: .hook(.working)),       // Tool 7
        SimEvent(time: 75, kind: .statusLine),
        SimEvent(time: 80, kind: .statusLine),
        // 15s think with streaming
        SimEvent(time: 85, kind: .hook(.working)),       // Tool 8
        SimEvent(time: 86, kind: .statusLine),
        SimEvent(time: 92, kind: .statusLine),
        SimEvent(time: 98, kind: .statusLine),
        SimEvent(time: 105, kind: .hook(.idle)),         // Stop
    ]

    for t in stride(from: 3.0, through: 104.0, by: 1.0) {
        let s = statusAt(t, events: events)
        check(s == .working, "SIM3 T=\(Int(t))s: must be working (got \(s))")
    }
    check(statusAt(105, events: events) == .idle, "SIM3 T=105: done")
}

section("SIM4: Repeated broken Stop hooks across turns")
do {
    let events: [SimEvent] = [
        SimEvent(time: 0,  kind: .hook(.idle)),
        // Turn 1: Stop fails
        SimEvent(time: 2,  kind: .hook(.working)),       // UserPromptSubmit
        SimEvent(time: 5,  kind: .hook(.working)),       // PreToolUse (last hook at T=5)
        SimEvent(time: 8,  kind: .statusLine),
        SimEvent(time: 11, kind: .statusLine),            // last reporter at T=11
        // Stop FAILS.
        // Turn 2 at T=60
        SimEvent(time: 60, kind: .hook(.working)),       // UserPromptSubmit
        SimEvent(time: 63, kind: .hook(.working)),       // PreToolUse (last hook at T=63)
        SimEvent(time: 66, kind: .statusLine),
        SimEvent(time: 69, kind: .statusLine),            // last reporter at T=69
        // Stop FAILS again.
    ]

    // Turn 1: hookAge > 10 at T=16, age > 8 at T=20. idle at max(16, 20) = 20.
    // Turn 2: hookAge > 10 at T=74, age > 8 at T=78. idle at max(74, 78) = 78.
    verify(events, [
        Expect(t: 5,  status: .working, reason: "turn 1 tool"),
        Expect(t: 15, status: .working, reason: "turn 1 hookAge=10 (threshold)"),
        Expect(t: 19, status: .working, reason: "turn 1 age=8 (threshold)"),
        Expect(t: 20, status: .idle,    reason: "turn 1 hookAge=15, age=9 → idle"),
        Expect(t: 50, status: .idle,    reason: "between turns"),
        Expect(t: 60, status: .working, reason: "turn 2 prompt"),
        Expect(t: 63, status: .working, reason: "turn 2 tool"),
        Expect(t: 77, status: .working, reason: "turn 2 age=8 (threshold)"),
        Expect(t: 78, status: .idle,    reason: "turn 2 hookAge=15, age=9 → idle"),
    ], label: "SIM4")
}

section("SIM5: Session idle for hours, then reactivated")
do {
    let events: [SimEvent] = [
        SimEvent(time: 0,    kind: .hook(.idle)),
        SimEvent(time: 5,    kind: .hook(.working)),
        SimEvent(time: 10,   kind: .hook(.idle)),         // Stop
        SimEvent(time: 3610, kind: .hook(.working)),      // UserPromptSubmit
        SimEvent(time: 3615, kind: .hook(.working)),      // PreToolUse
        SimEvent(time: 3620, kind: .hook(.idle)),         // Stop
    ]

    verify(events, [
        Expect(t: 10,   status: .idle,    reason: "done"),
        Expect(t: 3600, status: .idle,    reason: "idle 1 hour"),
        Expect(t: 3610, status: .working, reason: "reactivated"),
        Expect(t: 3620, status: .idle,    reason: "done again"),
    ], label: "SIM5")
}

// ============================================================
// MARK: - KNOWN LIMITATIONS (documented, accepted trade-offs)
// ============================================================

section("KNOWN1: Extended thinking >10s without streaming — briefly shows idle")
do {
    // Claude thinks 20s between tools. hookAge exceeds threshold.
    // The reporter does NOT fire during thinking (only during streaming).
    // Both hookAge and age grow, so the dual check fires.
    // In practice, the reporter likely fires during thinking (status line animation),
    // so this scenario mostly doesn't occur. Self-corrects on next tool.
    let events: [SimEvent] = [
        SimEvent(time: 0,  kind: .hook(.idle)),
        SimEvent(time: 1,  kind: .hook(.working)),
        SimEvent(time: 3,  kind: .hook(.working)),       // PreToolUse (last hook at T=3)
        SimEvent(time: 4,  kind: .statusLine),            // last reporter at T=4
        // 20s of pure thinking — no hooks, no reporter
        SimEvent(time: 23, kind: .hook(.working)),       // next PreToolUse
    ]

    // hookAge > 10 at T=14 (from T=3). age > 8 at T=13 (from T=4).
    // False idle at max(14, 13) = T=14.
    check(statusAt(10, events: events) == .working, "KNOWN1 T=10: hookAge=7, still working")
    check(statusAt(13, events: events) == .working, "KNOWN1 T=13: hookAge=10 (threshold)")
    check(statusAt(14, events: events) == .idle,    "KNOWN1 T=14: false idle (hookAge=11, age=10>8)")
    check(statusAt(23, events: events) == .working, "KNOWN1 T=23: self-corrects on next tool")
}

section("KNOWN2: Long subagent >10s without intermediate hooks or reporter")
do {
    let events: [SimEvent] = [
        SimEvent(time: 0,  kind: .hook(.idle)),
        SimEvent(time: 2,  kind: .hook(.working)),
        SimEvent(time: 5,  kind: .hook(.working)),       // SubagentStart (last hook at T=5)
        SimEvent(time: 6,  kind: .statusLine),            // last reporter at T=6
        // Subagent runs 25s with no events
        SimEvent(time: 30, kind: .hook(.working)),       // SubagentStop
    ]

    // hookAge > 10 at T=16 (from T=5). age > 8 at T=15 (from T=6).
    // False idle at max(16, 15) = T=16.
    check(statusAt(15, events: events) == .working, "KNOWN2 T=15: hookAge=10 (threshold)")
    check(statusAt(16, events: events) == .idle,    "KNOWN2 T=16: false idle during subagent")
    check(statusAt(30, events: events) == .working, "KNOWN2 T=30: self-corrects")
}

// ============================================================
// MARK: - UNIT TESTS
// ============================================================

section("Unit: hookAge boundary values")
check(computeStatus(hookState: .working, hookAge: 9.999, age: 20, processAlive: true) == .working, "hookAge=9.999 → working")
check(computeStatus(hookState: .working, hookAge: 10.0,  age: 20, processAlive: true) == .working, "hookAge=10.0 → working (not >)")
check(computeStatus(hookState: .working, hookAge: 10.001, age: 20, processAlive: true) == .idle,   "hookAge=10.001 age=20 → idle")

section("Unit: age threshold for staleness (age must also exceed threshold)")
check(computeStatus(hookState: .working, hookAge: 60, age: 0, processAlive: true) == .working,  "hookAge=60 age=0 → working (reporter just fired)")
check(computeStatus(hookState: .working, hookAge: 60, age: 5, processAlive: true) == .working,  "hookAge=60 age=5 → working")
check(computeStatus(hookState: .working, hookAge: 60, age: 7, processAlive: true) == .working,  "hookAge=60 age=7 → working")
check(computeStatus(hookState: .working, hookAge: 60, age: 8, processAlive: true) == .working,  "hookAge=60 age=8 → working (not >)")
check(computeStatus(hookState: .working, hookAge: 60, age: 9, processAlive: true) == .idle,     "hookAge=60 age=9 → idle")

section("Unit: stale working + dead process → disconnected")
check(computeStatus(hookState: .working, hookAge: 11, age: 9, processAlive: false) == .disconnected, "stale + dead → disconnected")

section("Unit: nil hookAge → no staleness check, regardless of age")
check(computeStatus(hookState: .working, hookAge: nil, age: 0,   processAlive: true) == .working, "nil hookAge age=0")
check(computeStatus(hookState: .working, hookAge: nil, age: 600, processAlive: true) == .working, "nil hookAge age=600")

section("Unit: staleness only applies to .working state")
check(computeStatus(hookState: .idle,              hookAge: 300, age: 300, processAlive: true) == .idle,      "idle: immune")
check(computeStatus(hookState: .waitingPermission, hookAge: 300, age: 300, processAlive: true) == .attention, "waitingPermission: immune")
check(computeStatus(hookState: .waitingInput,      hookAge: 300, age: 300, processAlive: true) == .attention, "waitingInput: immune")
check(computeStatus(hookState: .compacting,        hookAge: 300, age: 300, processAlive: true) == .working,   "compacting: immune")

section("Unit: sessionAction passes hookAge correctly")
if case .keep(let s) = sessionAction(hookState: .working, hookAge: 60, age: 60, processAlive: true) {
    check(s == .idle, "sessionAction hookAge=60 age=60 → idle")
} else { check(false, "should keep") }

// ============================================================
// MARK: - PARSING AND FORMATTING
// ============================================================

section("HookState raw values")
check(HookState(rawValue: "working") == .working, "working")
check(HookState(rawValue: "idle") == .idle, "idle")
check(HookState(rawValue: "waiting_permission") == .waitingPermission, "waiting_permission")
check(HookState(rawValue: "waiting_input") == .waitingInput, "waiting_input")
check(HookState(rawValue: "compacting") == .compacting, "compacting")
check(HookState(rawValue: "unknown") == nil, "unknown → nil")

section("parseHookStateFile")
do {
    let r = parseHookStateFile(#"{"state":"working","context":"Edit file.swift","last_message":"Done.","agents":[{"id":"a1","type":"Bash"}]}"#)
    check(r.state == .working && r.context == "Edit file.swift" && r.lastMessage == "Done.", "full JSON")
    check(r.activeAgents.count == 1 && r.activeAgents[0].type == "Bash", "agents")

    let r2 = parseHookStateFile(#"{"state":"idle","context":"","last_message":""}"#)
    check(r2.context == nil && r2.lastMessage == nil, "empty → nil")

    check(parseHookStateFile("working\n").state == .working, "plain text")
    check(parseHookStateFile("garbage").state == nil, "garbage → nil")
}

section("formatRelativeTime")
check(formatRelativeTime(0) == "just now", "0s")
check(formatRelativeTime(9.9) == "just now", "9.9s")
check(formatRelativeTime(10) == "10s", "10s")
check(formatRelativeTime(60) == "1m", "60s")
check(formatRelativeTime(3600) == "1h", "3600s")
check(formatRelativeTime(86400) == "1d", "86400s")

section("AgentStatus.displayOrder")
check(AgentStatus.displayOrder == [.attention, .working, .idle, .disconnected], "order")

section("Thresholds")
check(hookStaleThresholdSeconds == 10, "hookStale=10")
check(reporterStaleThresholdSeconds == 8, "reporterStale=8")
check(workingThresholdSeconds == 3, "working=3")
check(livenessCheckThresholdSeconds == 5, "liveness=5")
check(deadCleanupThresholdSeconds == 300, "cleanup=300")

// ============================================================
print("")
if failed == 0 {
    print("All \(passed) tests passed.")
} else {
    print("\(failed) FAILED, \(passed) passed.")
    exit(1)
}
