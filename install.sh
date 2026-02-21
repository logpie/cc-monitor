#!/bin/bash
set -euo pipefail

echo "Building CC Monitor..."
cd "$(dirname "$0")"
swift build -c release

# Install the app binary
INSTALL_DIR="$HOME/.local/bin"
mkdir -p "$INSTALL_DIR"
cp .build/release/CCMonitor "$INSTALL_DIR/cc-monitor"

# Install the reporter script
cp reporter/monitor-reporter.sh "$HOME/.claude/monitor-reporter.sh"
chmod +x "$HOME/.claude/monitor-reporter.sh"

# Create monitor directory
mkdir -p "$HOME/.claude/monitor"

echo ""
echo "=== CC Monitor installed ==="
echo ""
echo "Next steps:"
echo "  1. Add to ~/.claude/settings.json:"
echo '     "statusLine": { "type": "command", "command": "~/.claude/monitor-reporter.sh" }'
echo "  2. Run: cc-monitor"
echo "  3. (Optional) Enable 'Launch at Login' from the app's Settings (Cmd+,)"
