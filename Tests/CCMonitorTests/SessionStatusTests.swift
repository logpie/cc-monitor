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

    // Must stay attention indefinitely — user may be AFK, and hiding the
    // reminder would be worse than a false positive during tool execution.
    // Known limitation: after user approves a long tool (no "approved" event),
    // state stays waiting_permission until PostToolUse fires.
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
    // hookAge grows past 7, but age peaks at exactly 7 (not > 7 with strict compare).
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

    // hookAge exceeds 7 after T=10, but age peaks at exactly 7 (not > 7).
    // At worst: T=18-epsilon, age=7-epsilon which is NOT > 7. Must stay working.
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

    // Fast path: hookAge > age+2 (reporter was streaming), age > 6.
    // hookAge=16 > age=7+2=9 at T=21. age=7 > 6. Detection at T=21.
    check(statusAt(15, events: events) == .working, "LAG2 T=15: hookAge=10, age=1")
    check(statusAt(20, events: events) == .working, "LAG2 T=20: hookAge=15, age=6 (not > 6)")
    check(statusAt(21, events: events) == .idle,    "LAG2 T=21: fast path → idle")
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

    // Fast path: hookAge-age = 13 > 2 (reporter streamed after hook), age > 6.
    // age > 6 at T=25 (from T=18). Detection at T=25.
    check(statusAt(22, events: events) == .working, "LAG3 T=22: age=4 (not yet stale)")
    check(statusAt(24, events: events) == .working, "LAG3 T=24: age=6, at fast-path threshold")
    check(statusAt(25, events: events) == .idle,    "LAG3 T=25: fast path → idle")
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

    // Fast path: hookAge-age = 6 > 2 (reporter streamed after hook), age > 6.
    // age > 6 at T=18 (from T=11). Detection at T=18.
    check(statusAt(15, events: events) == .working, "SP2 T=15: hookAge=10, age=4")
    check(statusAt(17, events: events) == .working, "SP2 T=17: age=6, at fast-path threshold")
    check(statusAt(18, events: events) == .idle,    "SP2 T=18: fast path → idle")
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
    check(statusAt(135, events: events) == .working, "SP5 T=135: hookAge=7, age still fresh")
    // Fast path: hookAge-age = 8 > 2 (reporter streamed after hook), age > 6.
    // age > 6 at T=143 (from T=136). Detection at T=143.
    check(statusAt(142, events: events) == .working, "SP5 T=142: age=6, at fast-path threshold")
    check(statusAt(143, events: events) == .idle,    "SP5 T=143: fast path → idle")
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

    // hookAge - age = 2.0 (not > 2.0) → thinking path (12s threshold).
    // In practice, PostToolUseFailure or idle_prompt fires for faster detection.
    check(statusAt(14, events: events) == .working, "SP7 T=14: hookAge=10, age=8, both < 12 → working")
    check(statusAt(16, events: events) == .working, "SP7 T=16: hookAge=12, age=10, hookAge not > 12 → working")
    check(statusAt(19, events: events) == .idle,    "SP7 T=19: hookAge=15>12, age=13>12 → idle")
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

    // Turn 1: Fast path hookAge-age=6 > 2, age > 6 at T=18. idle at T=18.
    // Turn 2: Fast path hookAge-age=6 > 2, age > 6 at T=76. idle at T=76.
    verify(events, [
        Expect(t: 5,  status: .working, reason: "turn 1 tool"),
        Expect(t: 15, status: .working, reason: "turn 1 hookAge=10, age=4"),
        Expect(t: 17, status: .working, reason: "turn 1 age=6 (fast-path threshold)"),
        Expect(t: 18, status: .idle,    reason: "turn 1 fast path → idle"),
        Expect(t: 50, status: .idle,    reason: "between turns"),
        Expect(t: 60, status: .working, reason: "turn 2 prompt"),
        Expect(t: 63, status: .working, reason: "turn 2 tool"),
        Expect(t: 75, status: .working, reason: "turn 2 age=6 (fast-path threshold)"),
        Expect(t: 76, status: .idle,    reason: "turn 2 fast path → idle"),
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
// MARK: - THINKING PHASE TESTS
// Extended thinking uses 12s threshold — accepts brief false idle during long thinks.
// ============================================================

section("THINK1: Short thinking 10s — stays working (within 12s threshold)")
do {
    // Claude thinks 10s between tools. Well within 12s threshold.
    let events: [SimEvent] = [
        SimEvent(time: 0,  kind: .hook(.idle)),
        SimEvent(time: 1,  kind: .hook(.working)),
        SimEvent(time: 3,  kind: .hook(.working)),       // PreToolUse (last hook at T=3)
        SimEvent(time: 4,  kind: .statusLine),            // last reporter at T=4
        // 10s of pure thinking — no hooks, no reporter
        SimEvent(time: 13, kind: .hook(.working)),       // next PreToolUse
    ]

    // hookAge - age = 1.0 (not > 2.0) → thinking path (12s threshold).
    // 10s think is within 12s → stays working throughout.
    for t in stride(from: 3.0, through: 12.0, by: 1.0) {
        let s = statusAt(t, events: events)
        check(s == .working, "THINK1 T=\(Int(t))s: thinking, must be working (got \(s))")
    }
    check(statusAt(13, events: events) == .working, "THINK1 T=13: next tool → still working")
}

section("THINK2: Subagent 10s without events — stays working")
do {
    // Subagent runs 10s without any hooks or reporter updates.
    // hookAge - age = 1.0 → thinking path (12s). Within threshold.
    let events: [SimEvent] = [
        SimEvent(time: 0,  kind: .hook(.idle)),
        SimEvent(time: 2,  kind: .hook(.working)),
        SimEvent(time: 5,  kind: .hook(.working)),       // SubagentStart (last hook at T=5)
        SimEvent(time: 6,  kind: .statusLine),            // last reporter at T=6
        // Subagent runs 10s with no events
        SimEvent(time: 15, kind: .hook(.working)),       // SubagentStop
    ]

    for t in stride(from: 5.0, through: 14.0, by: 1.0) {
        let s = statusAt(t, events: events)
        check(s == .working, "THINK2 T=\(Int(t))s: subagent running, must be working (got \(s))")
    }
    check(statusAt(15, events: events) == .working, "THINK2 T=15: SubagentStop → working")
}

section("THINK3: Extended thinking 30s — shows idle then recovers on next tool")
do {
    // Opus can think for 30-120s. With 12s threshold, we accept brief false idle.
    // This is cosmetic — user is waiting anyway. Recovery is instant on next event.
    let events: [SimEvent] = [
        SimEvent(time: 0,  kind: .hook(.idle)),
        SimEvent(time: 2,  kind: .hook(.working)),       // UserPromptSubmit
        SimEvent(time: 5,  kind: .hook(.working)),       // PreToolUse
        SimEvent(time: 6,  kind: .statusLine),            // last reporter
        // 30s of thinking
        SimEvent(time: 35, kind: .hook(.working)),       // next PreToolUse
        SimEvent(time: 40, kind: .hook(.idle)),           // Stop
    ]

    // Within 12s threshold — working
    for t in stride(from: 5.0, through: 16.0, by: 1.0) {
        let s = statusAt(t, events: events)
        check(s == .working, "THINK3 T=\(Int(t))s: within threshold, working (got \(s))")
    }
    // After 12s — false idle (accepted trade-off)
    check(statusAt(19, events: events) == .idle,    "THINK3 T=19: hookAge=14>12, age=13>12 → idle (false)")
    check(statusAt(30, events: events) == .idle,    "THINK3 T=30: still idle during thinking")
    // Recovery on next hook event
    check(statusAt(35, events: events) == .working, "THINK3 T=35: next tool → recovery")
    check(statusAt(40, events: events) == .idle,    "THINK3 T=40: done")
}

section("THINK4: Thinking threshold boundary — exact 12s vs 13s")
do {
    // Precise boundary test for the 12s thinking threshold.
    let events: [SimEvent] = [
        SimEvent(time: 0,  kind: .hook(.idle)),
        SimEvent(time: 2,  kind: .hook(.working)),
        SimEvent(time: 5,  kind: .hook(.working)),       // PreToolUse (last hook at T=5)
        SimEvent(time: 6,  kind: .statusLine),            // last reporter at T=6
        // Long silence
        SimEvent(time: 50, kind: .hook(.working)),       // recovery
    ]

    // At T=17: hookAge=12, age=11. hookAge NOT > 12 → working
    check(statusAt(17, events: events) == .working, "THINK4 T=17: hookAge=12 (not >12) → working")
    // At T=18: hookAge=13>12, age=12. age NOT > 12 → working
    check(statusAt(18, events: events) == .working, "THINK4 T=18: age=12 (not >12) → working")
    // At T=19: hookAge=14>12, age=13>12 → idle
    check(statusAt(19, events: events) == .idle,    "THINK4 T=19: both > 12 → idle")
    check(statusAt(30, events: events) == .idle,    "THINK4 T=30: still idle")
    check(statusAt(50, events: events) == .working, "THINK4 T=50: recovery")
}

section("THINK5: No reporter fire after hook — hookAge = age, 12s threshold")
do {
    // When the tool completes instantly (PostToolUse fires), and no reporter
    // fires before thinking starts, hookAge and age grow at the same rate.
    let events: [SimEvent] = [
        SimEvent(time: 0,  kind: .hook(.idle)),
        SimEvent(time: 2,  kind: .hook(.working)),       // UserPromptSubmit
        SimEvent(time: 5,  kind: .hook(.working)),       // PreToolUse + PostToolUse (fast tool)
        // No reporter fire after T=5. hookAge = age.
        SimEvent(time: 30, kind: .hook(.working)),       // next tool
    ]

    // Within 12s: working
    for t in stride(from: 5.0, through: 17.0, by: 1.0) {
        let s = statusAt(t, events: events)
        check(s == .working, "THINK5 T=\(Int(t))s: hookAge=age, within threshold (got \(s))")
    }
    // After 12s: idle (hookAge=age=13 > 12)
    check(statusAt(18, events: events) == .idle, "THINK5 T=18: hookAge=age=13>12 → idle")
    check(statusAt(30, events: events) == .working, "THINK5 T=30: recovery")
}

section("THINK6: Active subagents suppress thinking-path idle fallback")
do {
    // When subagents are known to be running, the thinking-path idle fallback
    // is suppressed — their presence proves the session is actively working.
    // This prevents false idle during long subagent runs (e.g., 60s+ agents).
    check(computeStatus(hookState: .working, hookAge: 20, age: 20, processAlive: true, hasActiveAgents: false) == .idle,
          "THINK6: no agents, both > 12 → idle")
    check(computeStatus(hookState: .working, hookAge: 20, age: 20, processAlive: true, hasActiveAgents: true) == .working,
          "THINK6: agents active, both > 12 → still working")
    check(computeStatus(hookState: .working, hookAge: 120, age: 120, processAlive: true, hasActiveAgents: true) == .working,
          "THINK6: agents active, 120s → still working")
    // Streaming fast-path is NOT affected by agents (if reporter proved streaming then stopped)
    check(computeStatus(hookState: .working, hookAge: 60, age: 10, processAlive: true, hasActiveAgents: true) == .idle,
          "THINK6: streaming stopped, agents don't override fast-path")
}

// ============================================================
// MARK: - UNIT TESTS
// ============================================================

section("Unit: fast path — streaming proven (hookAge > age + 2)")
check(computeStatus(hookState: .working, hookAge: 60, age: 0, processAlive: true) == .working,  "hookAge=60 age=0 → working (streaming, not stale)")
check(computeStatus(hookState: .working, hookAge: 60, age: 5, processAlive: true) == .working,  "hookAge=60 age=5 → working")
check(computeStatus(hookState: .working, hookAge: 60, age: 6, processAlive: true) == .working,  "hookAge=60 age=6 → working (not > 6)")
check(computeStatus(hookState: .working, hookAge: 60, age: 7, processAlive: true) == .idle,     "hookAge=60 age=7 → idle (fast path, age > 6)")
check(computeStatus(hookState: .working, hookAge: 60, age: 8, processAlive: true) == .idle,     "hookAge=60 age=8 → idle")

section("Unit: fast path boundary — hookAge must exceed age + 2")
check(computeStatus(hookState: .working, hookAge: 9, age: 7, processAlive: true) == .working,     "hookAge-age=2, exactly at boundary → working (thinking path)")
check(computeStatus(hookState: .working, hookAge: 9.001, age: 7, processAlive: true) == .idle,    "hookAge-age=2.001, past boundary → idle (fast path)")
check(computeStatus(hookState: .working, hookAge: 8, age: 7, processAlive: true) == .working,     "hookAge-age=1, thinking path → working")

section("Unit: thinking path — no streaming (hookAge - age <= 2)")
check(computeStatus(hookState: .working, hookAge: 8, age: 7, processAlive: true) == .working,      "hookAge=8 age=7 → working (thinking, <12s)")
check(computeStatus(hookState: .working, hookAge: 8.001, age: 7.001, processAlive: true) == .working, "hookAge=8 age=7 → working (thinking, <12s)")
check(computeStatus(hookState: .working, hookAge: 12, age: 11, processAlive: true) == .working,    "hookAge=12 age=11 → working (hookAge not > 12)")
check(computeStatus(hookState: .working, hookAge: 13, age: 12, processAlive: true) == .working,    "hookAge=13 age=12 → working (age not > 12)")
check(computeStatus(hookState: .working, hookAge: 13, age: 13, processAlive: true) == .idle,       "hookAge=13 age=13 → idle (both > 12)")
check(computeStatus(hookState: .working, hookAge: 120, age: 120, processAlive: true) == .idle,     "hookAge=120 age=120 → idle (long stale)")
// hookAge < age: hook fired more recently than reporter (normal after hook event)
check(computeStatus(hookState: .working, hookAge: 7, age: 20, processAlive: true) == .working,     "hookAge=7 age=20 → working (thinking, hookAge<12)")

section("Unit: stale working + dead process → disconnected")
// Dead process is caught at the top of computeStatus regardless of thinking threshold
check(computeStatus(hookState: .working, hookAge: 8, age: 8, processAlive: false) == .disconnected, "stale + dead → disconnected (age>5, dead)")
check(computeStatus(hookState: .working, hookAge: 61, age: 61, processAlive: false) == .disconnected, "thinking-stale + dead → disconnected")

section("Unit: nil hookAge → no staleness check, regardless of age")
check(computeStatus(hookState: .working, hookAge: nil, age: 0,   processAlive: true) == .working, "nil hookAge age=0")
check(computeStatus(hookState: .working, hookAge: nil, age: 600, processAlive: true) == .working, "nil hookAge age=600")

section("Unit: staleness only applies to .working state")
check(computeStatus(hookState: .idle,              hookAge: 300, age: 300, processAlive: true) == .idle,      "idle: immune")
check(computeStatus(hookState: .waitingPermission, hookAge: 300, age: 300, processAlive: true) == .attention, "waitingPermission: immune")
check(computeStatus(hookState: .waitingInput,      hookAge: 300, age: 300, processAlive: true) == .attention, "waitingInput: immune")
check(computeStatus(hookState: .compacting,        hookAge: 300, age: 300, processAlive: true) == .working,   "compacting: immune")

section("Unit: sessionAction passes hookAge correctly")
if case .keep(let s) = sessionAction(hookState: .working, hookAge: 61, age: 61, processAlive: true) {
    check(s == .idle, "sessionAction hookAge=61 age=61 → idle (thinking path)")
} else { check(false, "should keep") }
if case .keep(let s) = sessionAction(hookState: .working, hookAge: 100, age: 10, processAlive: true) {
    check(s == .idle, "sessionAction hookAge=100 age=10 → idle (streaming fast path)")
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
check(thinkingStaleThresholdSeconds == 12, "thinkingStale=12")
check(streamStopStaleSeconds == 6, "streamStop=6")
check(workingThresholdSeconds == 3, "working=3")
check(livenessCheckThresholdSeconds == 5, "liveness=5")
check(deadCleanupThresholdSeconds == 300, "cleanup=300")

// ============================================================
// MARK: - PERMISSION RACE AND PID TESTS
// ============================================================

section("RACE1: Late notification_permission suppressed — state stays working")
do {
    // Models the FIXED behavior: Notification(permission_prompt) fires ~6s after
    // PermissionRequest, but the hook script suppresses it when state is "working".
    // Result: no hook(.waitingPermission) at T=14, so state stays working.
    let events: [SimEvent] = [
        SimEvent(time: 0,  kind: .hook(.idle)),
        SimEvent(time: 5,  kind: .hook(.waitingPermission)),  // PermissionRequest
        SimEvent(time: 8,  kind: .hook(.working)),            // User approves → PreToolUse
        SimEvent(time: 10, kind: .statusLine),                // Reporter fires during tool
        // T=14: Late Notification(permission_prompt) — suppressed by hook script
        // (no event here because the write is skipped)
        SimEvent(time: 15, kind: .statusLine),
        SimEvent(time: 20, kind: .hook(.idle)),               // Stop
    ]

    check(statusAt(5,  events: events) == .attention, "RACE1 T=5: permission requested")
    check(statusAt(8,  events: events) == .working,   "RACE1 T=8: approved → working")
    check(statusAt(14, events: events) == .working,   "RACE1 T=14: late notification suppressed, still working")
    check(statusAt(20, events: events) == .idle,       "RACE1 T=20: stop → idle")
}

section("RACE2: notification_permission arrives when NOT working — takes effect")
do {
    // When the session is idle and notification_permission arrives (no prior working),
    // the hook script should let it through as waiting_permission.
    let events: [SimEvent] = [
        SimEvent(time: 0,  kind: .hook(.idle)),
        SimEvent(time: 5,  kind: .hook(.waitingPermission)),  // notification_permission → falls through
    ]

    check(statusAt(5, events: events) == .attention, "RACE2 T=5: notification accepted when not working")
}

section("Unit: SessionInfo JSON with and without pid")
do {
    let jsonWithPid = """
    {"session_id":"abc","project_name":"test","project_dir":"/tmp","git_branch":"main",
     "git_dirty":0,"git_staged":0,"git_untracked":0,"model":"test",
     "context_used_pct":50,"context_window_size":200000,"cost_usd":1.0,
     "last_updated":1000,"tty":"/dev/ttys001","pid":12345,
     "tmux_target":"","tmux_window_name":"","tab_title":"","ghostty_window":"","ghostty_tab":""}
    """.data(using: .utf8)!
    let s1 = try! JSONDecoder().decode(SessionInfo.self, from: jsonWithPid)
    check(s1.pid == 12345, "pid parsed correctly")

    let jsonWithoutPid = """
    {"session_id":"abc","project_name":"test","project_dir":"/tmp","git_branch":"main",
     "git_dirty":0,"git_staged":0,"git_untracked":0,"model":"test",
     "context_used_pct":50,"context_window_size":200000,"cost_usd":1.0,
     "last_updated":1000,"tty":"/dev/ttys001",
     "tmux_target":"","tmux_window_name":"","tab_title":"","ghostty_window":"","ghostty_tab":""}
    """.data(using: .utf8)!
    let s2 = try! JSONDecoder().decode(SessionInfo.self, from: jsonWithoutPid)
    check(s2.pid == nil, "pid nil when absent (backward compat)")
}

section("Unit: Orphan/dead process → disconnected via computeStatus")
do {
    // When isProcessAlive detects PPID=1 or PID gone, processAlive=false.
    // computeStatus should return .disconnected when age > liveness threshold.
    check(computeStatus(hookState: .working, hookAge: 0, age: 6, processAlive: false) == .disconnected,
          "orphan: working → disconnected")
    check(computeStatus(hookState: .idle, hookAge: 0, age: 6, processAlive: false) == .disconnected,
          "orphan: idle → disconnected")
    check(computeStatus(hookState: .waitingPermission, hookAge: 0, age: 6, processAlive: false) == .disconnected,
          "orphan: waiting_permission → disconnected")
    // Young session (age < threshold) — process assumed alive regardless
    check(computeStatus(hookState: .working, hookAge: 0, age: 2, processAlive: false) == .working,
          "young session: processAlive ignored")
}

// ============================================================
print("")
if failed == 0 {
    print("All \(passed) tests passed.")
} else {
    print("\(failed) FAILED, \(passed) passed.")
    exit(1)
}
