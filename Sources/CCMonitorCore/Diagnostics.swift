import Foundation
import ApplicationServices

// MARK: - Types

public enum CheckSeverity: Comparable {
    case pass, warn, fail
}

public enum FixAction {
    case installHookScripts
    case fixPermissions(path: String)
    case createMonitorDir
    case mergeSettingsHooks
    case cleanFiles(paths: [String])
}

public struct CheckResult {
    public let name: String
    public let severity: CheckSeverity
    public let message: String
    public let detail: String?
    public let fixAction: FixAction?

    public init(name: String, severity: CheckSeverity, message: String, detail: String? = nil, fixAction: FixAction? = nil) {
        self.name = name
        self.severity = severity
        self.message = message
        self.detail = detail
        self.fixAction = fixAction
    }
}

public struct DiagnosticReport {
    public let checks: [CheckResult]

    public var hasCriticalIssues: Bool {
        checks.contains { $0.severity == .fail }
    }

    public var passCount: Int { checks.filter { $0.severity == .pass }.count }
    public var warnCount: Int { checks.filter { $0.severity == .warn }.count }
    public var failCount: Int { checks.filter { $0.severity == .fail }.count }
}

// MARK: - Expected hooks configuration

public struct ExpectedHook {
    public let event: String
    public let matcher: String
    public let command: String
}

public let expectedHooks: [ExpectedHook] = [
    ExpectedHook(event: "UserPromptSubmit", matcher: ".*", command: "~/.claude/monitor-hook.sh working"),
    ExpectedHook(event: "PreToolUse", matcher: ".*", command: "~/.claude/monitor-hook.sh working"),
    ExpectedHook(event: "Stop", matcher: ".*", command: "~/.claude/monitor-hook.sh idle"),
    ExpectedHook(event: "Notification", matcher: "permission_prompt", command: "~/.claude/monitor-hook.sh notification_permission"),
    ExpectedHook(event: "Notification", matcher: "idle_prompt", command: "~/.claude/monitor-hook.sh idle"),
    ExpectedHook(event: "PermissionRequest", matcher: ".*", command: "~/.claude/monitor-hook.sh waiting_permission"),
    ExpectedHook(event: "SubagentStart", matcher: ".*", command: "~/.claude/monitor-hook.sh subagent_start"),
    ExpectedHook(event: "SubagentStop", matcher: ".*", command: "~/.claude/monitor-hook.sh subagent_stop"),
    ExpectedHook(event: "PreCompact", matcher: ".*", command: "~/.claude/monitor-hook.sh compacting"),
    ExpectedHook(event: "SessionStart", matcher: ".*", command: "~/.claude/monitor-hook.sh idle"),
]

// MARK: - DiagnosticEngine

public final class DiagnosticEngine {
    private let home: String
    private let claudeDir: String
    private let monitorDir: String
    private let appBundleResourcesDir: String

    public init() {
        self.home = NSHomeDirectory()
        self.claudeDir = "\(NSHomeDirectory())/.claude"
        self.monitorDir = "\(NSHomeDirectory())/.claude/monitor"
        self.appBundleResourcesDir = "\(NSHomeDirectory())/Applications/CCMonitor.app/Contents/Resources"
    }

    /// Run all diagnostic checks. Safe to call from any thread.
    public func runAllChecks() -> DiagnosticReport {
        var checks: [CheckResult] = []

        checks += checkDependencies()
        checks += checkHookScripts()
        checks += checkSettings()
        checks += checkMonitorDir()
        checks += checkAccessibility()
        checks += checkDataIntegrity()
        checks += checkHookVersions()

        return DiagnosticReport(checks: checks)
    }

    /// Run only fast checks (dependencies, hooks, settings, directory). Skip data integrity.
    public func runFastChecks() -> DiagnosticReport {
        var checks: [CheckResult] = []

        checks += checkDependencies()
        checks += checkHookScripts()
        checks += checkSettings()
        checks += checkMonitorDir()

        return DiagnosticReport(checks: checks)
    }

    // MARK: - Individual check groups

    private func checkDependencies() -> [CheckResult] {
        var results: [CheckResult] = []

        // Check jq
        if let path = whichCommand("jq") {
            results.append(CheckResult(name: "jq", severity: .pass, message: "jq installed (\(path))"))
        } else {
            results.append(CheckResult(name: "jq", severity: .fail,
                message: "jq not found on PATH",
                detail: "Install with: brew install jq"))
        }

        // Check git
        if let path = whichCommand("git") {
            results.append(CheckResult(name: "git", severity: .pass, message: "git installed (\(path))"))
        } else {
            results.append(CheckResult(name: "git", severity: .fail,
                message: "git not found on PATH",
                detail: "Install with: xcode-select --install"))
        }

        return results
    }

    private func checkHookScripts() -> [CheckResult] {
        var results: [CheckResult] = []
        let fm = FileManager.default

        let hookPath = "\(claudeDir)/monitor-hook.sh"
        let reporterPath = "\(claudeDir)/monitor-reporter.sh"

        // monitor-hook.sh exists
        if fm.fileExists(atPath: hookPath) {
            results.append(CheckResult(name: "hook-exists", severity: .pass, message: "~/.claude/monitor-hook.sh exists"))
        } else {
            results.append(CheckResult(name: "hook-exists", severity: .fail,
                message: "~/.claude/monitor-hook.sh not found",
                detail: "Run: cc-monitor-doctor --fix to install",
                fixAction: .installHookScripts))
        }

        // monitor-hook.sh executable
        if fm.fileExists(atPath: hookPath) {
            if fm.isExecutableFile(atPath: hookPath) {
                results.append(CheckResult(name: "hook-exec", severity: .pass, message: "~/.claude/monitor-hook.sh is executable"))
            } else {
                results.append(CheckResult(name: "hook-exec", severity: .fail,
                    message: "~/.claude/monitor-hook.sh is not executable",
                    detail: "Run: cc-monitor-doctor --fix",
                    fixAction: .fixPermissions(path: hookPath)))
            }
        }

        // monitor-reporter.sh exists
        if fm.fileExists(atPath: reporterPath) {
            results.append(CheckResult(name: "reporter-exists", severity: .pass, message: "~/.claude/monitor-reporter.sh exists"))
        } else {
            results.append(CheckResult(name: "reporter-exists", severity: .fail,
                message: "~/.claude/monitor-reporter.sh not found",
                detail: "Run: cc-monitor-doctor --fix to install",
                fixAction: .installHookScripts))
        }

        // monitor-reporter.sh executable
        if fm.fileExists(atPath: reporterPath) {
            if fm.isExecutableFile(atPath: reporterPath) {
                results.append(CheckResult(name: "reporter-exec", severity: .pass, message: "~/.claude/monitor-reporter.sh is executable"))
            } else {
                results.append(CheckResult(name: "reporter-exec", severity: .fail,
                    message: "~/.claude/monitor-reporter.sh is not executable",
                    detail: "Run: cc-monitor-doctor --fix",
                    fixAction: .fixPermissions(path: reporterPath)))
            }
        }

        return results
    }

    private func checkSettings() -> [CheckResult] {
        var results: [CheckResult] = []
        let fm = FileManager.default
        let settingsPath = "\(claudeDir)/settings.json"

        // settings.json exists
        guard fm.fileExists(atPath: settingsPath) else {
            results.append(CheckResult(name: "settings-exists", severity: .fail,
                message: "~/.claude/settings.json not found",
                detail: "Run: cc-monitor-doctor --fix to create",
                fixAction: .mergeSettingsHooks))
            return results
        }
        results.append(CheckResult(name: "settings-exists", severity: .pass, message: "~/.claude/settings.json exists"))

        // Parse settings
        guard let data = fm.contents(atPath: settingsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            results.append(CheckResult(name: "settings-parse", severity: .fail,
                message: "~/.claude/settings.json is not valid JSON"))
            return results
        }

        // statusLine configured
        if let statusLine = json["statusLine"] as? [String: Any],
           let command = statusLine["command"] as? String,
           command.contains("monitor-reporter.sh") {
            results.append(CheckResult(name: "statusline", severity: .pass, message: "statusLine configured correctly"))
        } else {
            results.append(CheckResult(name: "statusline", severity: .fail,
                message: "statusLine not configured for CC Monitor",
                detail: "Run: cc-monitor-doctor --fix to configure",
                fixAction: .mergeSettingsHooks))
        }

        // Check each expected hook
        let hooks = json["hooks"] as? [String: Any] ?? [:]
        for expected in expectedHooks {
            let present = isHookPresent(hooks: hooks, event: expected.event, matcher: expected.matcher, command: expected.command)
            if present {
                results.append(CheckResult(name: "hook-\(expected.event)-\(expected.matcher)", severity: .pass,
                    message: "Hook \(expected.event) (\(expected.matcher)) configured"))
            } else {
                results.append(CheckResult(name: "hook-\(expected.event)-\(expected.matcher)", severity: .warn,
                    message: "Hook \(expected.event) (\(expected.matcher)) missing from settings",
                    detail: "Run: cc-monitor-doctor --fix to add",
                    fixAction: .mergeSettingsHooks))
            }
        }

        return results
    }

    private func checkMonitorDir() -> [CheckResult] {
        let fm = FileManager.default

        if fm.fileExists(atPath: monitorDir) {
            if fm.isWritableFile(atPath: monitorDir) {
                return [CheckResult(name: "monitor-dir", severity: .pass, message: "~/.claude/monitor/ exists and is writable")]
            } else {
                return [CheckResult(name: "monitor-dir", severity: .fail,
                    message: "~/.claude/monitor/ exists but is not writable",
                    fixAction: .createMonitorDir)]
            }
        } else {
            return [CheckResult(name: "monitor-dir", severity: .fail,
                message: "~/.claude/monitor/ directory not found",
                detail: "Run: cc-monitor-doctor --fix to create",
                fixAction: .createMonitorDir)]
        }
    }

    private func checkAccessibility() -> [CheckResult] {
        let trusted = AXIsProcessTrusted()
        if trusted {
            return [CheckResult(name: "accessibility", severity: .pass, message: "Accessibility permission granted")]
        } else {
            return [CheckResult(name: "accessibility", severity: .warn,
                message: "Accessibility permission not granted",
                detail: "Grant in: System Settings → Privacy & Security → Accessibility")]
        }
    }

    private func checkDataIntegrity() -> [CheckResult] {
        var results: [CheckResult] = []
        let fm = FileManager.default

        guard let files = try? fm.contentsOfDirectory(atPath: monitorDir) else {
            return results
        }

        var corruptJsonPaths: [String] = []
        var orphanedStatePaths: [String] = []

        let jsonFiles = files.filter { $0.hasSuffix(".json") && !$0.hasPrefix(".") }
        let stateFiles = files.filter { $0.hasSuffix(".state") && $0.hasPrefix(".") }

        // Check JSON files are valid
        for file in jsonFiles {
            let path = "\(monitorDir)/\(file)"
            if let data = fm.contents(atPath: path) {
                if (try? JSONSerialization.jsonObject(with: data)) == nil {
                    corruptJsonPaths.append(path)
                }
            }
        }

        // Check for orphaned .state files (no matching .json)
        for file in stateFiles {
            // .{session_id}.state → session_id
            let name = String(file.dropFirst(1).dropLast(6))
            let jsonName = "\(name).json"
            if !jsonFiles.contains(jsonName) {
                orphanedStatePaths.append("\(monitorDir)/\(file)")
            }
        }

        if corruptJsonPaths.isEmpty {
            results.append(CheckResult(name: "json-valid", severity: .pass, message: "All session .json files are valid"))
        } else {
            results.append(CheckResult(name: "json-valid", severity: .warn,
                message: "\(corruptJsonPaths.count) corrupt .json file(s) found",
                detail: corruptJsonPaths.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", "),
                fixAction: .cleanFiles(paths: corruptJsonPaths)))
        }

        if orphanedStatePaths.isEmpty {
            results.append(CheckResult(name: "orphan-state", severity: .pass, message: "No orphaned .state files"))
        } else {
            results.append(CheckResult(name: "orphan-state", severity: .warn,
                message: "\(orphanedStatePaths.count) orphaned .state file(s) found",
                detail: orphanedStatePaths.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", "),
                fixAction: .cleanFiles(paths: orphanedStatePaths)))
        }

        return results
    }

    private func checkHookVersions() -> [CheckResult] {
        var results: [CheckResult] = []
        let fm = FileManager.default

        let bundledHook = "\(appBundleResourcesDir)/monitor-hook.sh"
        let bundledReporter = "\(appBundleResourcesDir)/monitor-reporter.sh"
        let installedHook = "\(claudeDir)/monitor-hook.sh"
        let installedReporter = "\(claudeDir)/monitor-reporter.sh"

        for (name, bundled, installed) in [
            ("monitor-hook.sh", bundledHook, installedHook),
            ("monitor-reporter.sh", bundledReporter, installedReporter),
        ] {
            guard fm.fileExists(atPath: installed) else { continue }

            guard fm.fileExists(atPath: bundled) else {
                results.append(CheckResult(name: "version-\(name)", severity: .warn,
                    message: "\(name) version cannot be verified (no bundled copy)"))
                continue
            }

            let bundledContent = (try? String(contentsOfFile: bundled, encoding: .utf8)) ?? ""
            let installedContent = (try? String(contentsOfFile: installed, encoding: .utf8)) ?? ""

            if bundledContent == installedContent {
                results.append(CheckResult(name: "version-\(name)", severity: .pass,
                    message: "\(name) matches bundled version"))
            } else {
                results.append(CheckResult(name: "version-\(name)", severity: .warn,
                    message: "\(name) differs from bundled version",
                    detail: "Run: cc-monitor-doctor --fix to update",
                    fixAction: .installHookScripts))
            }
        }

        return results
    }

    // MARK: - Fix actions

    public func applyFix(_ action: FixAction) -> (success: Bool, message: String) {
        switch action {
        case .installHookScripts:
            return installHookScripts()
        case .fixPermissions(let path):
            return fixPermissions(path: path)
        case .createMonitorDir:
            return createMonitorDir()
        case .mergeSettingsHooks:
            return mergeSettingsHooks()
        case .cleanFiles(let paths):
            return cleanFiles(paths: paths)
        }
    }

    private func installHookScripts() -> (success: Bool, message: String) {
        let fm = FileManager.default
        let bundledHook = "\(appBundleResourcesDir)/monitor-hook.sh"
        let bundledReporter = "\(appBundleResourcesDir)/monitor-reporter.sh"
        let installedHook = "\(claudeDir)/monitor-hook.sh"
        let installedReporter = "\(claudeDir)/monitor-reporter.sh"

        guard fm.fileExists(atPath: bundledHook), fm.fileExists(atPath: bundledReporter) else {
            return (false, "Bundled hook scripts not found in app bundle Resources. Reinstall the app.")
        }

        do {
            // Remove existing before copy (copyItem fails if destination exists)
            if fm.fileExists(atPath: installedHook) { try fm.removeItem(atPath: installedHook) }
            try fm.copyItem(atPath: bundledHook, toPath: installedHook)

            if fm.fileExists(atPath: installedReporter) { try fm.removeItem(atPath: installedReporter) }
            try fm.copyItem(atPath: bundledReporter, toPath: installedReporter)

            // chmod +x
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installedHook)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installedReporter)

            return (true, "Installed hook scripts to ~/.claude/")
        } catch {
            return (false, "Failed to install hook scripts: \(error.localizedDescription)")
        }
    }

    private func fixPermissions(path: String) -> (success: Bool, message: String) {
        do {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
            return (true, "Fixed permissions on \(path)")
        } catch {
            return (false, "Failed to fix permissions: \(error.localizedDescription)")
        }
    }

    private func createMonitorDir() -> (success: Bool, message: String) {
        do {
            try FileManager.default.createDirectory(atPath: monitorDir, withIntermediateDirectories: true)
            return (true, "Created ~/.claude/monitor/")
        } catch {
            return (false, "Failed to create directory: \(error.localizedDescription)")
        }
    }

    private func mergeSettingsHooks() -> (success: Bool, message: String) {
        let settingsPath = "\(claudeDir)/settings.json"
        let fm = FileManager.default

        // Load existing settings or start fresh
        var settings: [String: Any] = [:]
        if fm.fileExists(atPath: settingsPath),
           let data = fm.contents(atPath: settingsPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = json
        }

        // Ensure statusLine
        settings["statusLine"] = [
            "type": "command",
            "command": "~/.claude/monitor-reporter.sh"
        ] as [String: Any]

        // Build/merge hooks
        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        for expected in expectedHooks {
            var eventEntries = hooks[expected.event] as? [[String: Any]] ?? []

            // Check if this exact hook already exists
            let alreadyPresent = eventEntries.contains { entry in
                guard let matcher = entry["matcher"] as? String, matcher == expected.matcher else { return false }
                guard let hookList = entry["hooks"] as? [[String: Any]] else { return false }
                return hookList.contains { h in
                    (h["command"] as? String) == expected.command
                }
            }

            if !alreadyPresent {
                // Check if there's an entry with this matcher we can append to
                var merged = false
                for i in eventEntries.indices {
                    if let matcher = eventEntries[i]["matcher"] as? String, matcher == expected.matcher {
                        var hookList = eventEntries[i]["hooks"] as? [[String: Any]] ?? []
                        hookList.append(["type": "command", "command": expected.command])
                        eventEntries[i]["hooks"] = hookList
                        merged = true
                        break
                    }
                }

                if !merged {
                    eventEntries.append([
                        "matcher": expected.matcher,
                        "hooks": [["type": "command", "command": expected.command]]
                    ] as [String: Any])
                }
            }

            hooks[expected.event] = eventEntries
        }

        settings["hooks"] = hooks

        // Write back
        do {
            let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: settingsPath))
            return (true, "Updated ~/.claude/settings.json with hook configuration")
        } catch {
            return (false, "Failed to write settings: \(error.localizedDescription)")
        }
    }

    private func cleanFiles(paths: [String]) -> (success: Bool, message: String) {
        let fm = FileManager.default
        var removed = 0
        for path in paths {
            do {
                try fm.removeItem(atPath: path)
                removed += 1
            } catch {
                // Continue cleaning other files
            }
        }
        return (true, "Removed \(removed) file(s)")
    }

    // MARK: - Helpers

    private func whichCommand(_ command: String) -> String? {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = [command]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }

        guard task.terminationStatus == 0 else { return nil }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return output?.isEmpty == false ? output : nil
    }

    private func isHookPresent(hooks: [String: Any], event: String, matcher: String, command: String) -> Bool {
        guard let entries = hooks[event] as? [[String: Any]] else { return false }
        for entry in entries {
            guard let m = entry["matcher"] as? String, m == matcher else { continue }
            if let hookList = entry["hooks"] as? [[String: Any]] {
                for h in hookList {
                    if let cmd = h["command"] as? String, cmd == command {
                        return true
                    }
                }
            }
        }
        return false
    }
}
