import SwiftUI

struct SessionListView: View {
    @ObservedObject var monitor: SessionMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if monitor.sessions.isEmpty {
                Text("No active Claude Code sessions")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ForEach(monitor.sessions) { session in
                    Text(session.projectName)
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                }
            }

            Divider()
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
                .padding(.horizontal)
                .padding(.vertical, 8)
        }
    }
}
