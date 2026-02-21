import SwiftUI

@main
struct CCMonitorApp: App {
    @StateObject private var monitor = SessionMonitor()

    var body: some Scene {
        MenuBarExtra {
            SessionListView(monitor: monitor)
                .frame(minWidth: 380, maxWidth: 380, minHeight: 100, maxHeight: 600)
        } label: {
            Image(nsImage: menuBarDotsImage(sessions: monitor.sessions))
        }
        .menuBarExtraStyle(.window)
    }
}
