# CC Monitor — Project Instructions

## Build & Test
```bash
swift build -c release          # Build release binary
swift run CCMonitorTests         # Run all tests (NOT swift test — custom test harness)
```

## Install after changes
```bash
cp .build/release/CCMonitor ~/Applications/CCMonitor.app/Contents/MacOS/CCMonitor
codesign --force --sign - ~/Applications/CCMonitor.app
# Restart: pkill -f CCMonitor.app/Contents/MacOS/CCMonitor && open ~/Applications/CCMonitor.app
```

## Architecture
- `Sources/CCMonitorCore/StatusLogic.swift` — Pure functions for status computation (testable, no I/O)
- `Sources/CCMonitorCore/SessionTypes.swift` — Data types (SessionInfo, AgentStatus, HookState)
- `Sources/CCMonitor/SessionMonitor.swift` — File watching, liveness checks, session loading
- `Sources/CCMonitor/SessionRowView.swift` — Individual session card UI
- `Sources/CCMonitor/SessionListView.swift` — Panel layout with grouped sections
- `Sources/CCMonitor/CCMonitorApp.swift` — App entry point, MenuBarExtra
- `Tests/CCMonitorTests/SessionStatusTests.swift` — Event-replay simulation tests
- `~/.claude/monitor-hook.sh` — Hook script (writes .state files, deployed separately)
- `~/.claude/monitor-reporter.sh` — statusLine reporter (writes .json files)

## Key design decisions
- **Two-tier idle detection**: Streaming fast-path (6s) + thinking/silence path (12s)
- **Active subagents suppress idle fallback**: If agents are running, session stays "Working" regardless of silence
- **Permission race suppression**: Late `notification_permission` events are dropped when state already moved past permission
- **"Needs Input" is highest priority**: Zero false positives — if it says attention needed, it's real
- **Project name as primary label**: Tab titles shown as secondary context, not primary identifier

## Testing conventions
- Tests use event-replay simulation (`SimEvent` + `statusAt()`) — NOT mocks
- Test names: `THINK1`, `SP7`, `RACE1`, `FP3`, etc. — short prefixes by category
- Always run `swift run CCMonitorTests` after StatusLogic changes
- SourceKit often shows false diagnostics — trust compiler output, not IDE errors

## Codex review workflow
After major changes, run Codex for multi-angle review:
- Codex PRs land on branches — review and cherry-pick useful changes
- Credit Codex in commit messages: "Inspired by Codex code review (PR #N)"
- Codex uses a different model which catches different edge cases
