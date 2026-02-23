import AppKit
import SwiftUI

let systemSounds = ["Glass", "Ping", "Pop", "Purr", "Submarine", "Blow", "Bottle", "Frog", "Funk", "Hero", "Morse", "Sosumi", "Tink", "Basso"]

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Prompt for Accessibility permissions (needed for tab clicking)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}

@main
struct CCMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var monitor = SessionMonitor()
    @State private var flashHidden = false
    @State private var flashTimer: Timer?
    @AppStorage("colorTheme") private var themeRaw = ColorTheme.dracula.rawValue
    @AppStorage("notificationSound") private var notificationSound = "Glass"

    private var theme: ColorTheme { ColorTheme(rawValue: themeRaw) ?? .dracula }

    private var hasAttention: Bool {
        monitor.sessions.contains { $0.cachedStatus == .attention }
    }

    var body: some Scene {
        MenuBarExtra {
            SessionListView(monitor: monitor, flashAttention: flashHidden)
                .frame(width: 380)
                .fixedSize(horizontal: false, vertical: true)
        } label: {
            Image(nsImage: menuBarDotsImage(
                sessions: monitor.sessions,
                flashAttention: flashHidden,
                theme: theme
            ))
            .onChange(of: hasAttention) { needsFlash in
                if needsFlash {
                    if !notificationSound.isEmpty, notificationSound != "None" {
                        NSSound(named: NSSound.Name(notificationSound))?.play()
                    }
                    flashTimer?.invalidate()
                    flashTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { _ in
                        Task { @MainActor in flashHidden.toggle() }
                    }
                } else {
                    flashTimer?.invalidate()
                    flashTimer = nil
                    flashHidden = false
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
