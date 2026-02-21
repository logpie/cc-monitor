import SwiftUI

struct SessionListView: View {
    @ObservedObject var monitor: SessionMonitor

    private var groupedSessions: [(status: AgentStatus, sessions: [SessionInfo])] {
        let grouped = Dictionary(grouping: monitor.sessions) { $0.cachedStatus }
        return AgentStatus.displayOrder
            .compactMap { status in
                guard let sessions = grouped[status], !sessions.isEmpty else { return nil }
                return (status, sessions.sorted { $0.projectName < $1.projectName })
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if monitor.sessions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.title2)
                        .foregroundStyle(.quaternary)
                    Text("No active sessions")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(groupedSessions, id: \.status) { group in
                            VStack(alignment: .leading, spacing: 4) {
                                // Section header with accent bar
                                HStack(spacing: 6) {
                                    RoundedRectangle(cornerRadius: 1.5)
                                        .fill(Color(nsColor: group.status.color))
                                        .frame(width: 3, height: 12)

                                    Text("\(group.status.sectionTitle) (\(group.sessions.count))")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.secondary)
                                        .textCase(.uppercase)
                                }
                                .padding(.horizontal, 12)
                                .padding(.bottom, 2)

                                // Session cards
                                VStack(spacing: 4) {
                                    ForEach(group.sessions) { session in
                                        SessionRowView(session: session)
                                            .id("\(session.cachedStatus.rawValue)-\(session.id)")
                                    }
                                }
                                .padding(.horizontal, 6)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onAppear { monitor.loadSessions(checkLiveness: false) }
            }

            Divider()

            HStack {
                let totalCost = monitor.sessions.reduce(0.0) { $0 + $1.costUsd }
                Text("\(monitor.sessions.count) session\(monitor.sessions.count == 1 ? "" : "s") · \(formatTotalCost(totalCost))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Usage") {
                    NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/usage")!)
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Text("·").foregroundStyle(.quaternary).font(.caption2)
                Button("Quit") { NSApp.terminate(nil) }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }
}

private func formatTotalCost(_ cost: Double) -> String {
    if cost >= 100 {
        return "$\(Int(cost)) total"
    } else if cost >= 10 {
        return String(format: "$%.1f total", cost)
    } else {
        return String(format: "$%.2f total", cost)
    }
}

extension AgentStatus {
    var sectionTitle: String {
        switch self {
        case .attention:    return "Needs Input"
        case .working:      return "Working"
        case .idle:         return "Ready"
        case .disconnected: return "Disconnected"
        }
    }
}
