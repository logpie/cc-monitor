import SwiftUI
import AppKit

struct SessionRowView: View {
    let session: SessionInfo
    let now: Date

    private var status: AgentStatus { session.status(now: now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Top line: dot + project (branch) + status
            HStack {
                Circle()
                    .fill(Color(nsColor: status.color))
                    .frame(width: 10, height: 10)
                    .modifier(PulseModifier(isActive: status == .error))

                HStack(spacing: 4) {
                    Text(session.projectName)
                        .font(.system(.body, weight: .semibold))
                    if !session.gitBranch.isEmpty {
                        Text("(\(session.gitBranch))")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text(status.displayText)
                    .font(.callout)
                    .foregroundStyle(status == .waiting ? .red : .secondary)
            }

            // Bottom line: context bar + model
            HStack(spacing: 12) {
                ContextBar(percentage: session.contextUsedPct)
                Text(session.model)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 22)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            TerminalFocuser.focus(session: session)
        }
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

extension AgentStatus {
    var displayText: String {
        switch self {
        case .working:  return "Working..."
        case .waiting:  return "Waiting for input"
        case .idle:     return "Idle"
        case .error:    return "Disconnected"
        }
    }
}

struct PulseModifier: ViewModifier {
    let isActive: Bool
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isActive ? (isPulsing ? 0.3 : 1.0) : 1.0)
            .animation(
                isActive
                    ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                    : .default,
                value: isPulsing
            )
            .onAppear { if isActive { isPulsing = true } }
            .onChange(of: isActive) { newValue in isPulsing = newValue }
    }
}
