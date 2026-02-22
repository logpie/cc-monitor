import Foundation
import CCMonitorCore

// MARK: - ANSI colors

let colorReset  = "\u{1b}[0m"
let colorRed    = "\u{1b}[31m"
let colorGreen  = "\u{1b}[32m"
let colorYellow = "\u{1b}[33m"
let colorBold   = "\u{1b}[1m"

func severityTag(_ severity: CheckSeverity) -> String {
    switch severity {
    case .pass: return "\(colorGreen)[PASS]\(colorReset)"
    case .warn: return "\(colorYellow)[WARN]\(colorReset)"
    case .fail: return "\(colorRed)[FAIL]\(colorReset)"
    }
}

// MARK: - Argument parsing

let args = CommandLine.arguments
let doFix = args.contains("--fix")
let verbose = args.contains("--verbose")
let showHelp = args.contains("--help") || args.contains("-h")

if showHelp {
    print("""
    Usage: cc-monitor-doctor [--fix] [--verbose]

    Diagnoses CC Monitor installation health.

    Options:
      --fix       Attempt to auto-repair fixable issues
      --verbose   Show passing checks too (default: only warnings and failures)
      -h, --help  Show this help
    """)
    exit(0)
}

// MARK: - Run diagnostics

print("\(colorBold)CC Monitor Doctor\(colorReset)")
print("=================")
print()

let engine = DiagnosticEngine()
let report = engine.runAllChecks()

// Track unique fix actions already applied (avoid running installHookScripts twice)
var appliedFixes: Set<String> = []

func fixKey(_ action: FixAction) -> String {
    switch action {
    case .installHookScripts: return "installHookScripts"
    case .fixPermissions(let p): return "fixPermissions:\(p)"
    case .createMonitorDir: return "createMonitorDir"
    case .mergeSettingsHooks: return "mergeSettingsHooks"
    case .cleanFiles(let p): return "cleanFiles:\(p.joined(separator: ","))"
    }
}

for check in report.checks {
    // In non-verbose mode, skip passing checks
    if !verbose && check.severity == .pass { continue }

    print("  \(severityTag(check.severity)) \(check.message)")

    if let detail = check.detail {
        print("         \(detail)")
    }

    // Apply fix if --fix and there's a fix action
    if doFix, let action = check.fixAction, check.severity != .pass {
        let key = fixKey(action)
        if !appliedFixes.contains(key) {
            appliedFixes.insert(key)
            let result = engine.applyFix(action)
            if result.success {
                print("         \(colorGreen)Fixed:\(colorReset) \(result.message)")
            } else {
                print("         \(colorRed)Fix failed:\(colorReset) \(result.message)")
            }
        }
    }
}

print()
print("Summary: \(report.passCount) passed, \(report.warnCount) warning\(report.warnCount == 1 ? "" : "s"), \(report.failCount) error\(report.failCount == 1 ? "" : "s")")

if doFix && !appliedFixes.isEmpty {
    print()
    print("Re-running checks after fixes...")
    print()

    let recheck = engine.runAllChecks()
    for check in recheck.checks {
        if !verbose && check.severity == .pass { continue }
        print("  \(severityTag(check.severity)) \(check.message)")
        if let detail = check.detail {
            print("         \(detail)")
        }
    }
    print()
    print("Summary: \(recheck.passCount) passed, \(recheck.warnCount) warning\(recheck.warnCount == 1 ? "" : "s"), \(recheck.failCount) error\(recheck.failCount == 1 ? "" : "s")")

    exit(recheck.hasCriticalIssues ? 1 : 0)
}

exit(report.hasCriticalIssues ? 1 : 0)
