import Foundation
import AppKit

enum TerminalFocuser {

    private static func log(_ msg: String) {
        let line = "[\(Date())] \(msg)\n"
        if let fh = FileHandle(forWritingAtPath: "/tmp/ccmonitor.log") {
            fh.seekToEndOfFile()
            fh.write(Data(line.utf8))
            try? fh.close()
        } else {
            FileManager.default.createFile(atPath: "/tmp/ccmonitor.log", contents: Data(line.utf8))
        }
    }

    static func focus(session: SessionInfo) {
        log("focus called: \(session.sessionId)")

        // Dismiss the menu bar panel
        NSApp.keyWindow?.close()

        let fallbackTitle = session.displayLabel
        let sessionId = session.sessionId
        let tty = session.tty
        let tmuxTarget = session.tmuxTarget

        // Run everything on a background thread, but dispatch AppleScript
        // calls to the main thread (NSAppleScript requires it).
        DispatchQueue.global(qos: .userInitiated).async {
            // For tmux: switch to the right pane first
            if let tmuxTarget = tmuxTarget, !tmuxTarget.isEmpty {
                switchTmuxPane(target: tmuxTarget)
            }

            // Determine the TTY for the Ghostty tab
            let targetTTY: String
            if let tmuxTarget = tmuxTarget, !tmuxTarget.isEmpty {
                let sessionName = String(tmuxTarget.split(separator: ":").first ?? "")
                let clientTTY = shellOutput(
                    "/usr/bin/env tmux list-clients -t '\(sessionName)' -F '#{client_tty}' 2>/dev/null | head -1")
                guard !clientTTY.isEmpty else {
                    runAppleScriptOnMain("tell application \"Ghostty\" to activate")
                    return
                }
                targetTTY = clientTTY
            } else if let tty = tty, !tty.isEmpty {
                targetTTY = tty
            } else {
                runAppleScriptOnMain("tell application \"Ghostty\" to activate")
                return
            }

            log("targeting tty=\(targetTTY)")
            focusGhosttyTab(tty: targetTTY, sessionId: sessionId, fallbackTitle: fallbackTitle)
        }
    }

    // MARK: - tmux

    private static func switchTmuxPane(target: String) {
        let parts = target.split(separator: ":")
        guard parts.count == 2 else { return }
        let sessionName = String(parts[0])
        let windowPane = String(parts[1])
        let wpParts = windowPane.split(separator: ".")

        shellRun("tmux select-window -t '\(sessionName):\(wpParts[0])' 2>/dev/null")
        if wpParts.count > 1 {
            shellRun("tmux select-pane -t '\(target)' 2>/dev/null")
        }
    }

    // MARK: - Ghostty tab focus

    private static func focusGhosttyTab(tty: String, sessionId: String, fallbackTitle: String) {
        let tag = "ccmon-\(sessionId.prefix(8))"

        // 1. Write tag to TTY
        guard writeToTTY(tty, "\u{1b}]0;\(tag)\u{07}") else {
            log("failed to write tag to TTY")
            runAppleScriptOnMain("tell application \"Ghostty\" to activate")
            return
        }

        // 2. Brief pause for Ghostty to process the escape sequences
        Thread.sleep(forTimeInterval: 0.05)

        // 3. Single AppleScript: find tagged tab, click it, bring window to front
        runAppleScriptOnMain("""
        tell application "System Events"
            tell process "ghostty"
                set windowCount to count of windows
                repeat with wIdx from 1 to windowCount
                    set w to window wIdx
                    try
                        set tg to UI element "tab bar" of w
                        set tabs to every radio button of tg
                        repeat with t in tabs
                            if name of t contains "\(tag)" then
                                click t
                                tell application "Ghostty" to activate
                                set index of w to 1
                                return "ok"
                            end if
                        end repeat
                    on error
                        if name of w contains "\(tag)" then
                            tell application "Ghostty" to activate
                            set index of w to 1
                            return "ok"
                        end if
                    end try
                end repeat
            end tell
        end tell
        tell application "Ghostty" to activate
        return ""
        """)

        // 4. Restore title (shell precmd will override on next prompt)
        writeToTTY(tty, "\u{1b}]0;\(fallbackTitle)\u{07}")
    }

    // MARK: - Helpers

    /// Run AppleScript via NSAppleScript on the main thread (inherits app's Accessibility permissions)
    @discardableResult
    private static func runAppleScriptOnMain(_ source: String) -> String {
        if Thread.isMainThread {
            return executeAppleScript(source)
        }
        var result = ""
        DispatchQueue.main.sync {
            result = executeAppleScript(source)
        }
        return result
    }

    private static func executeAppleScript(_ source: String) -> String {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return "" }
        let output = script.executeAndReturnError(&error)
        if let error = error {
            log("AppleScript error: \(error)")
        }
        return output.stringValue ?? ""
    }

    @discardableResult
    private static func writeToTTY(_ tty: String, _ escape: String) -> Bool {
        guard let fh = FileHandle(forWritingAtPath: tty) else { return false }
        fh.write(Data(escape.utf8))
        try? fh.close()
        return true
    }

    private static func shellRun(_ command: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", command]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
    }

    private static func shellOutput(_ command: String) -> String {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", command]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()
        return (String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
