#!/bin/bash
# CC Monitor installer
# Usage: curl -fsSL https://raw.githubusercontent.com/logpie/cc-monitor/main/install.sh | bash
set -euo pipefail

REPO_URL="https://github.com/logpie/cc-monitor.git"
APP_NAME="CCMonitor"
APP_DIR="$HOME/Applications/${APP_NAME}.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
CLAUDE_DIR="$HOME/.claude"
MONITOR_DIR="$CLAUDE_DIR/monitor"

# --- Helpers ---
info()  { echo "  → $1"; }
error() { echo "  ✗ $1" >&2; exit 1; }

# --- Check dependencies ---
echo "Checking dependencies..."
command -v swift &>/dev/null || error "Swift not found. Install Xcode or Command Line Tools: xcode-select --install"
command -v jq &>/dev/null    || error "jq not found. Install with: brew install jq"
command -v git &>/dev/null   || error "git not found. Install Xcode Command Line Tools: xcode-select --install"
info "swift, jq, git OK"

# --- Get source ---
# If we're already in the repo, use it. Otherwise clone to a temp dir.
if [ -f "Package.swift" ] && grep -q "CCMonitor" Package.swift 2>/dev/null; then
    SRC_DIR="$(pwd)"
    CLEANUP=false
    info "Using local source: $SRC_DIR"
else
    SRC_DIR=$(mktemp -d)
    CLEANUP=true
    echo "Cloning cc-monitor..."
    git clone --depth 1 "$REPO_URL" "$SRC_DIR"
fi

# --- Build ---
echo "Building (release)..."
cd "$SRC_DIR"
swift build -c release

# --- Install app bundle ---
echo "Installing app..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp .build/release/CCMonitor "$MACOS_DIR/$APP_NAME"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>CCMonitor</string>
    <key>CFBundleDisplayName</key>
    <string>CC Monitor</string>
    <key>CFBundleIdentifier</key>
    <string>com.ccmonitor.app</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>CCMonitor</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
PLIST

cp resources/AppIcon.icns "$RESOURCES_DIR/AppIcon.icns"
codesign --force --sign - "$APP_DIR"
info "Installed: $APP_DIR"

# --- Install hook scripts ---
echo "Installing hook scripts..."
mkdir -p "$MONITOR_DIR"

cp reporter/monitor-reporter.sh "$CLAUDE_DIR/monitor-reporter.sh"
chmod +x "$CLAUDE_DIR/monitor-reporter.sh"
info "Installed: ~/.claude/monitor-reporter.sh"

cp reporter/monitor-hook.sh "$CLAUDE_DIR/monitor-hook.sh"
chmod +x "$CLAUDE_DIR/monitor-hook.sh"
info "Installed: ~/.claude/monitor-hook.sh"

# --- Configure settings.json ---
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
HOOKS_CONFIG='{
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
}'

if [ -f "$SETTINGS_FILE" ]; then
    # Check if hooks are already configured
    if jq -e '.hooks' "$SETTINGS_FILE" &>/dev/null; then
        info "~/.claude/settings.json already has hooks configured — skipping"
        info "Review README.md if you need to update hook config"
    else
        # Merge our config into existing settings
        jq -s '.[0] * .[1]' "$SETTINGS_FILE" <(echo "$HOOKS_CONFIG") > "${SETTINGS_FILE}.tmp"
        mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
        info "Updated: ~/.claude/settings.json (added hooks + statusLine)"
    fi
else
    echo "$HOOKS_CONFIG" | jq '.' > "$SETTINGS_FILE"
    info "Created: ~/.claude/settings.json"
fi

# --- Cleanup temp clone ---
if [ "$CLEANUP" = true ]; then
    rm -rf "$SRC_DIR"
fi

# --- Done ---
echo ""
echo "=== CC Monitor installed ==="
echo ""
echo "  Launch:  open ~/Applications/CCMonitor.app"
echo ""
echo "  Grant Accessibility permissions when prompted (needed for terminal tab focusing)."
echo "  Restart active Claude Code sessions to pick up the new hooks."
echo ""
