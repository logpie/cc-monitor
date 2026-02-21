import Foundation
import AppKit

enum TerminalFocuser {
    /// Focus the terminal tab/pane containing the given session
    static func focus(session: SessionInfo) {
        if let tmuxTarget = session.tmuxTarget, !tmuxTarget.isEmpty {
            focusTmux(target: tmuxTarget)
        } else {
            focusGhosttyTab(session: session)
        }
    }

    /// For tmux sessions: select the right window/pane, then focus the terminal app
    private static func focusTmux(target: String) {
        // target is like "1:0.2" (session:window.pane)
        let parts = target.split(separator: ":")
        guard parts.count == 2 else { return }
        let sessionName = String(parts[0])
        let windowPane = String(parts[1])
        let wpParts = windowPane.split(separator: ".")

        // Select the tmux window and pane
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["tmux", "select-window", "-t", "\(sessionName):\(wpParts[0])"]
        try? task.run()
        task.waitUntilExit()

        if wpParts.count > 1 {
            let paneTask = Process()
            paneTask.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            paneTask.arguments = ["tmux", "select-pane", "-t", target]
            try? paneTask.run()
            paneTask.waitUntilExit()
        }

        // Now focus the terminal window containing tmux
        activateTerminalApp()
    }

    /// For Ghostty tabs: find the tab whose title matches the project and click it
    private static func focusGhosttyTab(session: SessionInfo) {
        // Claude Code sets the terminal tab title. We search for a tab whose title
        // contains the project name. We check all windows and tabs.
        let projectName = escapeForAppleScript(session.projectName)

        let script = """
        tell application "Ghostty" to activate
        delay 0.1
        tell application "System Events"
            tell process "ghostty"
                set windowCount to count of windows
                repeat with wIdx from 1 to windowCount
                    set w to window wIdx
                    try
                        set tg to UI element "tab bar" of w
                        set tabs to every radio button of tg
                        repeat with t in tabs
                            set tName to name of t
                            if tName contains "\(projectName)" then
                                click t
                                set index of w to 1
                                return "found"
                            end if
                        end repeat
                    on error
                        -- Window might have no tab bar (single tab)
                        -- Check the window title instead
                        set wName to name of w
                        if wName contains "\(projectName)" then
                            set index of w to 1
                            return "found"
                        end if
                    end try
                end repeat
            end tell
        end tell
        return "not_found"
        """

        runAppleScript(script)
    }

    /// Activate the frontmost terminal app (Ghostty)
    private static func activateTerminalApp() {
        runAppleScript("""
        tell application "Ghostty" to activate
        """)
    }

    private static func runAppleScript(_ source: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", source]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        // Don't wait - fire and forget to keep UI responsive
    }

    private static func escapeForAppleScript(_ s: String) -> String {
        return s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
