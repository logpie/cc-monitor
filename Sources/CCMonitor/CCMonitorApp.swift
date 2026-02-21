import SwiftUI

@main
struct CCMonitorApp: App {
    var body: some Scene {
        MenuBarExtra("CC Monitor", systemImage: "circle.fill") {
            Text("Hello from CC Monitor")
            Button("Quit") { NSApp.terminate(nil) }
        }
    }
}
