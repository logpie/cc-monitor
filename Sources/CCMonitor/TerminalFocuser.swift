import Foundation
import AppKit

enum TerminalFocuser {
    static func focus(session: SessionInfo) {
        if let tmuxTarget = session.tmuxTarget, !tmuxTarget.isEmpty {
            focusTmux(target: tmuxTarget)
        } else if let tty = session.tty, !tty.isEmpty {
            focusGhosttyByTTY(tty: tty)
        }
    }

    // MARK: - tmux

    private static func focusTmux(target: String) {
        let parts = target.split(separator: ":")
        guard parts.count == 2 else { return }
        let sessionName = String(parts[0])
        let windowPane = String(parts[1])
        let wpParts = windowPane.split(separator: ".")

        run("/usr/bin/env", args: ["tmux", "select-window", "-t", "\(sessionName):\(wpParts[0])"])
        if wpParts.count > 1 {
            run("/usr/bin/env", args: ["tmux", "select-pane", "-t", target])
        }

        // Focus the Ghostty window that contains tmux
        runAppleScript("""
        tell application "Ghostty" to activate
        delay 0.1
        tell application "System Events"
            tell process "ghostty"
                repeat with w in every window
                    try
                        set tg to UI element "tab bar" of w
                        repeat with t in every radio button of tg
                            if name of t contains "tmux" then
                                click t
                                set index of w to 1
                                return
                            end if
                        end repeat
                    on error
                        if name of w contains "tmux" then
                            set index of w to 1
                            return
                        end if
                    end try
                end repeat
            end tell
        end tell
        """)
    }

    // MARK: - Ghostty by TTY

    /// Maps TTY -> Ghostty tab by:
    /// 1. Finding Ghostty's PID
    /// 2. Listing all Ghostty child processes (one login per tab) with their TTYs
    /// 3. Listing all Ghostty tabs across windows
    /// 4. Matching by position (tabs ordered same as child processes per window)
    private static func focusGhosttyByTTY(tty: String) {
        // Step 1: Get ordered list of Ghostty tab TTYs
        // Each tab spawns a login process as a direct child of Ghostty
        let ttyShort = tty.replacingOccurrences(of: "/dev/", with: "")

        // Get Ghostty PID
        let ghosttyPid = runCapture("/usr/bin/pgrep", args: ["-x", "ghostty"]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ghosttyPid.isEmpty else {
            runAppleScript("tell application \"Ghostty\" to activate")
            return
        }

        // Get all tab TTYs (child processes of Ghostty, sorted by PID = creation order)
        let psOutput = runCapture("/bin/ps", args: ["-eo", "pid=,ppid=,tty="])
        var ttyList: [String] = []
        for line in psOutput.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 3 else { continue }
            let ppid = String(parts[1])
            if ppid == ghosttyPid {
                ttyList.append(String(parts[2]))
            }
        }

        // Step 2: Get Ghostty tab info via AppleScript
        let tabInfo = runCaptureAppleScript("""
        set output to ""
        tell application "System Events"
            tell process "ghostty"
                set windowCount to count of windows
                repeat with wIdx from 1 to windowCount
                    set w to window wIdx
                    try
                        set tg to UI element "tab bar" of w
                        set tabs to every radio button of tg
                        repeat with t in tabs
                            set output to output & wIdx & "\\t" & (name of t) & linefeed
                        end repeat
                    on error
                        set output to output & wIdx & "\\t" & (name of w) & linefeed
                    end try
                end repeat
            end tell
        end tell
        return output
        """)

        // Parse tab info into (windowIdx, tabIdx, title)
        struct TabEntry {
            let windowIdx: Int
            let tabIdx: Int
            let title: String
        }
        var tabs: [TabEntry] = []
        var tabCountPerWindow: [Int: Int] = [:]
        for line in tabInfo.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2, let wIdx = Int(parts[0]) else { continue }
            let count = (tabCountPerWindow[wIdx] ?? 0) + 1
            tabCountPerWindow[wIdx] = count
            tabs.append(TabEntry(windowIdx: wIdx, tabIdx: count, title: String(parts[1])))
        }

        // Step 3: Match TTY to tab
        // The TTY list from ps is in PID order (tab creation order across all windows).
        // The tab list from AppleScript is in display order (window by window, tab by tab).
        // These should correspond 1:1.
        if let ttyIndex = ttyList.firstIndex(of: ttyShort), ttyIndex < tabs.count {
            let tab = tabs[ttyIndex]
            let script = """
            tell application "Ghostty" to activate
            delay 0.1
            tell application "System Events"
                tell process "ghostty"
                    set w to window \(tab.windowIdx)
                    set index of w to 1
                    try
                        set tg to UI element "tab bar" of w
                        set tabs to every radio button of tg
                        if (count of tabs) >= \(tab.tabIdx) then
                            click item \(tab.tabIdx) of tabs
                        end if
                    end try
                end tell
            end tell
            """
            runAppleScript(script)
        } else {
            // Fallback: just activate Ghostty
            runAppleScript("tell application \"Ghostty\" to activate")
        }
    }

    // MARK: - Helpers

    private static func run(_ path: String, args: [String]) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
    }

    private static func runCapture(_ path: String, args: [String]) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private static func runAppleScript(_ source: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", source]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
    }

    private static func runCaptureAppleScript(_ source: String) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", source]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
