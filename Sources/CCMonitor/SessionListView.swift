import SwiftUI

struct SessionListView: View {
    @ObservedObject var monitor: SessionMonitor
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if monitor.sessions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No active sessions")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(monitor.sessions) { session in
                            SessionRowView(session: session, now: now)
                            if session.id != monitor.sessions.last?.id {
                                Divider().padding(.horizontal, 12)
                            }
                        }
                    }
                }
            }

            Divider()

            HStack {
                Text("Last updated: just now")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .onReceive(timer) { self.now = $0 }
    }
}
