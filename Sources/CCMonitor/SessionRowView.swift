import SwiftUI
import AppKit

struct SessionRowView: View {
    let session: SessionInfo
    @State private var isHovered = false

    private var status: AgentStatus { session.cachedStatus }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Line 1: dot + name + branch + git status + status + time
            HStack(spacing: 5) {
                Circle()
                    .fill(Color(nsColor: status.color))
                    .frame(width: 7, height: 7)

                Text(session.projectName)
                    .font(.system(.callout, weight: .medium))
                    .lineLimit(1)

                if !session.gitBranch.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 8))
                        Text(session.gitBranch)
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(3)
                    .lineLimit(1)
                }

                if let gitStatus = session.gitStatusSummary {
                    Text(gitStatus)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .monospacedDigit()
                }

                Spacer()

                Text(session.detailedStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(session.relativeTime)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            // Line 2: path · model · context bar · cost
            HStack(spacing: 0) {
                Text(session.displayPath)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)

                Text("  ·  ")
                    .foregroundStyle(.quaternary)

                Text(session.model)
                    .foregroundStyle(.secondary)

                Text("  ·  ")
                    .foregroundStyle(.quaternary)

                contextView

                Text("  ·  ")
                    .foregroundStyle(.quaternary)

                Text(formatCost(session.costUsd))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .padding(.leading, 14)

            // Line 3: last task context (persists across state changes)
            if let context = session.hookContext, !context.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: contextIcon(for: context))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Text(context)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 14)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.primary.opacity(0.08) : Color.primary.opacity(0.03))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            TerminalFocuser.focus(session: session)
        }
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    @ViewBuilder
    private var contextView: some View {
        let pct = session.contextUsedPct
        let color: Color = pct >= 85 ? .red : pct >= 60 ? .orange : .secondary

        HStack(spacing: 3) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.primary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(color.opacity(pct >= 60 ? 1.0 : 0.5))
                        .frame(width: geo.size.width * min(pct / 100, 1.0))
                }
            }
            .frame(width: 40, height: 4)

            Text("\(Int(pct))%")
                .monospacedDigit()
                .foregroundStyle(color)
        }
    }

    private func contextIcon(for context: String) -> String {
        if context.hasPrefix("Edit") || context.hasPrefix("Write") { return "pencil" }
        if context.hasPrefix("Read") { return "doc.text" }
        if context.hasPrefix("$") { return "terminal" }
        if context.hasPrefix("Search") { return "magnifyingglass" }
        if context.hasPrefix("Agent") { return "person.2" }
        if context.contains("web") || context.contains("Web") || context.contains("Fetch") { return "globe" }
        return "gearshape"
    }

    private func formatCost(_ cost: Double) -> String {
        if cost >= 100 {
            return "$\(Int(cost))"
        } else if cost >= 10 {
            return String(format: "$%.1f", cost)
        } else {
            return String(format: "$%.2f", cost)
        }
    }
}
