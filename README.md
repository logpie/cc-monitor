# CC Monitor

A macOS menu bar app that monitors all your active [Claude Code](https://docs.anthropic.com/en/docs/claude-code) sessions in real time.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)
![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-orange)

## Features

- **Menu bar status pills** — at-a-glance counts for working, idle, and attention-needed sessions
- **Flashing alert** — menu bar flashes orange/red when a session needs permission or input
- **Session cards** grouped by status, showing:
  - Project name, path, and relative time since last activity
  - Git branch + staged/dirty/untracked counts
  - Model name, context window usage bar, and accumulated cost
  - Current task context (e.g. "Edit StatusDot.swift", "$ npm test")
  - Last assistant response (when idle)
- **Click to focus** — click any session to switch to its terminal tab (Ghostty, tmux, or plain terminal)
- **9 color themes** — Dracula, Tokyo Night, One Dark, Catppuccin, Gruvbox, Nord, Solarized, Monokai, and macOS Native. Themes cover the entire panel: background, text, icons, cards, status dots, git colors, and context bar
- **Adjustable transparency** — slider to control panel background opacity
- **Launch at Login** support

## Requirements

- macOS 13.0+
- Swift 5.9+
- [jq](https://jqlang.github.io/jq/) (`brew install jq`)
- Claude Code CLI

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/logpie/cc-monitor/main/install.sh | bash
```

This clones the repo, builds the app, installs it to `~/Applications/CCMonitor.app`, sets up hook scripts, and configures `~/.claude/settings.json` automatically.

Or manually:

```bash
git clone https://github.com/logpie/cc-monitor.git
cd cc-monitor
bash install.sh
```

After installing, launch the app and grant Accessibility permissions when prompted (needed for terminal tab focusing):

```bash
open ~/Applications/CCMonitor.app
```

Restart any active Claude Code sessions to pick up the new hooks.

## Troubleshooting

CC Monitor ships with a diagnostic tool that checks your installation health and can auto-repair most issues:

```bash
cc-monitor-doctor           # Check for problems
cc-monitor-doctor --verbose # Show all checks (including passing)
cc-monitor-doctor --fix     # Auto-repair fixable issues
```

It verifies: dependencies (jq, git), hook scripts installed and executable, settings.json configured correctly, monitor directory writable, Accessibility permissions, data file integrity, and hook script versions.

If the app detects issues on startup, a yellow warning triangle appears in the footer bar — click it for instructions.

<details>
<summary>What the installer configures in ~/.claude/settings.json</summary>

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/monitor-reporter.sh"
  },
  "hooks": {
    "UserPromptSubmit": [
      { "matcher": ".*", "hooks": [{ "type": "command", "command": "~/.claude/monitor-hook.sh working" }] }
    ],
    "PreToolUse": [
      { "matcher": ".*", "hooks": [{ "type": "command", "command": "~/.claude/monitor-hook.sh working" }] }
    ],
    "Stop": [
      { "matcher": ".*", "hooks": [{ "type": "command", "command": "~/.claude/monitor-hook.sh idle" }] }
    ],
    "Notification": [
      { "matcher": "permission_prompt", "hooks": [{ "type": "command", "command": "~/.claude/monitor-hook.sh notification_permission" }] },
      { "matcher": "idle_prompt", "hooks": [{ "type": "command", "command": "~/.claude/monitor-hook.sh idle" }] }
    ],
    "PermissionRequest": [
      { "matcher": ".*", "hooks": [{ "type": "command", "command": "~/.claude/monitor-hook.sh waiting_permission" }] }
    ],
    "SubagentStart": [
      { "matcher": ".*", "hooks": [{ "type": "command", "command": "~/.claude/monitor-hook.sh subagent_start" }] }
    ],
    "SubagentStop": [
      { "matcher": ".*", "hooks": [{ "type": "command", "command": "~/.claude/monitor-hook.sh subagent_stop" }] }
    ],
    "PreCompact": [
      { "matcher": ".*", "hooks": [{ "type": "command", "command": "~/.claude/monitor-hook.sh compacting" }] }
    ],
    "SessionStart": [
      { "matcher": ".*", "hooks": [{ "type": "command", "command": "~/.claude/monitor-hook.sh idle" }] }
    ]
  }
}
```

> **Note:** `notification_permission` (not `waiting_permission`) is intentional for `Notification(permission_prompt)`. The hook script suppresses late notification events when the session has already moved to `working` or `idle`, preventing stale "Needs Input" flashing.

</details>

## How it works

```
Claude Code sessions
    │
    ├─ statusLine hook → monitor-reporter.sh
    │   Writes session metadata (model, cost, git, context %)
    │   to ~/.claude/monitor/{session_id}.json
    │
    └─ lifecycle hooks → monitor-hook.sh
        Writes agent state (working/idle/waiting_permission)
        and task context to ~/.claude/monitor/.{session_id}.state

CCMonitor.app
    │
    ├─ Watches ~/.claude/monitor/ for file changes
    ├─ Refreshes every 1s, liveness checks every 10s
    ├─ Renders menu bar pills + session dropdown
    └─ Click → focuses terminal via AppleScript / TTY escape codes
```

## Status detection behavior

CC Monitor infers session state from hook events and file timestamps. Most transitions are instant, but there are inherent trade-offs:

| Transition | Latency | How it works |
|---|---|---|
| **Idle → Working** | Instant | `UserPromptSubmit` hook fires immediately |
| **Working → Needs Input** | Instant | `PermissionRequest` hook fires immediately |
| **Working → Ready** (normal) | Instant | `Stop` hook fires when Claude finishes its turn |
| **Working → Ready** (no Stop) | ~12s | If the `Stop` hook fails to fire (known edge case), staleness detection kicks in after ~12s of silence |
| **Extended thinking** | May briefly show Ready | During long thinking phases (30-120s for Opus), neither hooks nor the status reporter fire. The session may briefly appear "Ready" until streaming begins. Recovery is instant once output starts. |
| **Subagent running** | Stays Working | Active subagents are tracked explicitly — sessions with running subagents stay "Working" regardless of silence duration |
| **Disconnected** | ~5s | Detected via process liveness check (PID-based with PPID=1 orphan detection, TTY fallback) |

**Design priority:** "Needs Input" (permission/input prompts) is the highest-priority signal and has zero false positives — if the menu bar says a session needs attention, it genuinely does. The trade-off is that brief false "Ready" during extended thinking is accepted as cosmetic.

## Known limitations

These are caused by gaps in Claude Code's upstream hook system, not by CC Monitor itself:

- **No `Stop` hook on user interrupt (Escape/Ctrl+C):** Claude Code does not fire the `Stop` hook when the user interrupts a response. CC Monitor falls back to staleness detection (~12s). If `Notification(idle_prompt)` fires, detection is instant.
- **No "permission approved" event:** When the user approves a permission prompt, Claude Code fires `PreToolUse` (which transitions to "Working"), but there is no dedicated "approved" event. For long-running tools (e.g., a Bash command that takes minutes), the state correctly shows "Working" after `PreToolUse` fires. However, if `PreToolUse` is delayed or missed, the session may briefly stay on "Needs Input."
- **Extended thinking is indistinguishable from idle:** During Claude's thinking phase (before streaming starts), no hooks or status updates fire. This looks identical to an idle session from the outside. CC Monitor uses a 12s silence threshold as a compromise — long thinking phases (common with Opus) may briefly show "Ready."
- **`Notification(permission_prompt)` fires late (~6s):** This upstream notification arrives ~6s after `PermissionRequest`. The hook script suppresses it when the session has already moved past the permission state, but the delay means CC Monitor relies on `PermissionRequest` (which is instant) as the primary signal.
- **statusLine reporter only fires during streaming:** The reporter that writes session metadata (model, cost, context %) only updates while Claude is actively streaming output. During thinking, tool execution, or idle periods, metadata may be stale.

## License

MIT
