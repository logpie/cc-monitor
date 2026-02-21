import SwiftUI
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from Dock (no Info.plist in SPM)
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct CCMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var monitor = SessionMonitor()

    var body: some Scene {
        MenuBarExtra {
            SessionListView(monitor: monitor)
                .frame(minWidth: 380, maxWidth: 380, minHeight: 100, maxHeight: 600)
        } label: {
            Image(nsImage: menuBarDotsImage(sessions: monitor.sessions))
        }
        .menuBarExtraStyle(.window)

        Settings {
            VStack(spacing: 12) {
                Toggle("Launch at Login", isOn: Binding(
                    get: { SMAppService.mainApp.status == .enabled },
                    set: { newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            print("Failed to update login item: \(error)")
                        }
                    }
                ))
            }
            .padding()
            .frame(width: 250, height: 80)
        }
    }
}
