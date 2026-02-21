import SwiftUI

struct SessionListView: View {
    @ObservedObject var monitor: SessionMonitor
    var flashAttention: Bool = false
    @AppStorage("colorTheme") private var themeRaw = ColorTheme.dracula.rawValue
    @AppStorage("panelOpacity") private var panelOpacity = 0.82
    @State private var showThemePicker = false

    private var theme: ColorTheme { ColorTheme(rawValue: themeRaw) ?? .dracula }

    private var groupedSessions: [(status: AgentStatus, sessions: [SessionInfo])] {
        let grouped = Dictionary(grouping: monitor.sessions) { $0.cachedStatus }
        return AgentStatus.displayOrder
            .compactMap { status in
                guard let sessions = grouped[status], !sessions.isEmpty else { return nil }
                return (status, sessions.sorted { $0.lastUpdated > $1.lastUpdated })
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if monitor.sessions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.title2)
                        .foregroundStyle(theme.tertiaryText)
                    Text("No active sessions")
                        .font(.callout)
                        .foregroundStyle(theme.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(groupedSessions, id: \.status) { group in
                            VStack(alignment: .leading, spacing: 4) {
                                // Section header with accent bar
                                HStack(spacing: 6) {
                                    let isFlashing = group.status == .attention && flashAttention
                                    RoundedRectangle(cornerRadius: 1.5)
                                        .fill(Color(nsColor: isFlashing
                                            ? theme.flashColor
                                            : group.status.color(for: theme)))
                                        .frame(width: 3, height: 12)

                                    Text("\(group.status.sectionTitle) (\(group.sessions.count))")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(theme.secondaryText)
                                        .textCase(.uppercase)
                                }
                                .padding(.horizontal, 12)
                                .padding(.bottom, 2)

                                // Session cards
                                VStack(spacing: 3) {
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

            // Themed divider
            Rectangle()
                .fill(theme.dividerColor)
                .frame(height: 1)
                .padding(.horizontal, 8)

            // Footer
            HStack(spacing: 12) {
                let totalCost = monitor.sessions.reduce(0.0) { $0 + $1.costUsd }
                Text("\(monitor.sessions.count) session\(monitor.sessions.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(theme.tertiaryText)

                Text(formatTotalCost(totalCost))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(theme.tertiaryText)

                Spacer()

                Button {
                    showThemePicker.toggle()
                } label: {
                    Image(systemName: "paintpalette")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.accent)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showThemePicker, arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(ColorTheme.allCases, id: \.rawValue) { t in
                            Button {
                                themeRaw = t.rawValue
                                showThemePicker = false
                            } label: {
                                HStack(spacing: 6) {
                                    Text(t.displayName)
                                        .font(.caption2)
                                    Spacer()
                                    if t.rawValue == themeRaw {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 8, weight: .bold))
                                    }
                                }
                                .foregroundStyle(t.rawValue == themeRaw ? theme.primaryText : theme.secondaryText)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }

                        Rectangle()
                            .fill(theme.dividerColor)
                            .frame(height: 1)
                            .padding(.horizontal, 8)
                            .padding(.top, 4)

                        HStack(spacing: 6) {
                            Image(systemName: "circle.righthalf.filled")
                                .font(.system(size: 8))
                                .foregroundStyle(theme.secondaryText)
                            Slider(value: $panelOpacity, in: 0.4...1.0)
                                .controlSize(.mini)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                    }
                    .padding(.vertical, 4)
                    .frame(width: 130)
                    .background(theme.panelBackground(opacity: panelOpacity))
                }

                Button {
                    NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/usage")!)
                } label: {
                    Text("Usage")
                        .font(.caption2)
                        .foregroundStyle(theme.secondaryText)
                }
                .buttonStyle(.plain)

                Button {
                    NSApp.terminate(nil)
                } label: {
                    Text("Quit")
                        .font(.caption2)
                        .foregroundStyle(theme.secondaryText)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(theme.panelBackground(opacity: panelOpacity))
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
