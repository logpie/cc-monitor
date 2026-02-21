#!/bin/bash
set -euo pipefail

echo "Building CC Monitor..."
cd "$(dirname "$0")"
swift build -c release

APP_NAME="CCMonitor"
APP_DIR="$HOME/Applications/${APP_NAME}.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# Create .app bundle structure
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# Copy binary and ad-hoc sign (so macOS tracks Accessibility permissions consistently)
cp .build/release/CCMonitor "$MACOS_DIR/$APP_NAME"
codesign --force --sign - "$APP_DIR"

# Create Info.plist
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
</dict>
</plist>
PLIST

# Install the reporter script
cp reporter/monitor-reporter.sh "$HOME/.claude/monitor-reporter.sh"
chmod +x "$HOME/.claude/monitor-reporter.sh"

# Create monitor directory
mkdir -p "$HOME/.claude/monitor"

echo ""
echo "=== CC Monitor installed ==="
echo "  App: $APP_DIR"
echo ""
echo "Next steps:"
echo "  1. Add to ~/.claude/settings.json:"
echo '     "statusLine": { "type": "command", "command": "~/.claude/monitor-reporter.sh" }'
echo "  2. Launch: open ~/Applications/CCMonitor.app"
echo "  3. (Optional) Enable 'Launch at Login' from the app's Settings (Cmd+,)"
