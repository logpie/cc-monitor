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
git clone https://github.com/logpie/cc-monitor.git
cd cc-monitor
bash install.sh
```

This builds the app, installs it to `~/Applications/CCMonitor.app`, and sets up the reporter script.

## Setup

Add the following to your `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/monitor-reporter.sh"
  },
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": ".*",
        "hooks": [{ "type": "command", "command": "~/.claude/monitor-hook.sh working" }]
      }
    ],
    "PreToolUse": [
      {
        "matcher": ".*",
        "hooks": [{ "type": "command", "command": "~/.claude/monitor-hook.sh working" }]
      }
    ],
    "Stop": [
      {
        "matcher": ".*",
        "hooks": [{ "type": "command", "command": "~/.claude/monitor-hook.sh idle" }]
      }
    ],
    "Notification": [
      {
        "matcher": "permission_prompt",
        "hooks": [{ "type": "command", "command": "~/.claude/monitor-hook.sh waiting_permission" }]
      },
      {
        "matcher": "idle_prompt",
        "hooks": [{ "type": "command", "command": "~/.claude/monitor-hook.sh idle" }]
      }
    ],
    "PermissionRequest": [
      {
        "matcher": ".*",
        "hooks": [{ "type": "command", "command": "~/.claude/monitor-hook.sh waiting_permission" }]
      }
    ],
    "SubagentStart": [
      {
        "matcher": ".*",
        "hooks": [{ "type": "command", "command": "~/.claude/monitor-hook.sh subagent_start" }]
      }
    ],
    "SubagentStop": [
      {
        "matcher": ".*",
        "hooks": [{ "type": "command", "command": "~/.claude/monitor-hook.sh subagent_stop" }]
      }
    ],
    "PreCompact": [
      {
        "matcher": ".*",
        "hooks": [{ "type": "command", "command": "~/.claude/monitor-hook.sh compacting" }]
      }
    ],
    "SessionStart": [
      {
        "matcher": ".*",
        "hooks": [{ "type": "command", "command": "~/.claude/monitor-hook.sh idle" }]
      }
    ]
  }
}
```

Then install the hook script:

```bash
cp reporter/monitor-hook.sh ~/.claude/monitor-hook.sh
chmod +x ~/.claude/monitor-hook.sh
```

Launch the app:

```bash
open ~/Applications/CCMonitor.app
```

Grant Accessibility permissions when prompted (needed for terminal tab focusing).

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

## License

MIT
