import SwiftUI
import AppKit

struct SessionRowView: View {
    let session: SessionInfo
    @State private var isHovered = false

    private var status: AgentStatus { session.cachedStatus }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Row 1: dot + name + path + time
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(nsColor: status.color))
                    .frame(width: 7, height: 7)

                Text(session.displayLabel)
                    .font(.system(.callout, weight: .medium))
                    .lineLimit(1)

                Text(session.displayPath)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)

                Spacer(minLength: 4)

                Text(session.relativeTime)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 28, alignment: .trailing)
            }

            // Row 2: branch + git status
            if !session.gitBranch.isEmpty {
                HStack(spacing: 6) {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 8))
                        Text(session.gitBranch)
                    }
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                    if (session.gitStaged ?? 0) > 0 {
                        Text("+\(session.gitStaged!)")
                            .foregroundStyle(.green)
                            .monospacedDigit()
                    }
                    if (session.gitDirty ?? 0) > 0 {
                        Text("~\(session.gitDirty!)")
                            .foregroundStyle(.red)
                            .monospacedDigit()
                    }
                    if (session.gitUntracked ?? 0) > 0 {
                        Text("?\(session.gitUntracked!)")
                            .foregroundStyle(.blue)
                            .monospacedDigit()
                    }
                }
                .font(.caption2)
                .padding(.leading, 13)
            }

            // Row 3: task context (persists across state changes)
            if let context = session.hookContext, !context.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: contextIcon(for: context))
                        .font(.system(size: 9))
                        .foregroundStyle(.primary)
                    Text(context)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.leading, 13)
            }

            // Row 4: last response from Claude
            if let msg = session.lastMessage, !msg.isEmpty {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 7))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                    Text(msg)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.leading, 13)
            }

            // Row 5: model · context bar · cost (always last)
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "cpu")
                        .font(.system(size: 9))
                        .foregroundStyle(.primary)
                    Text(session.model)
                        .foregroundStyle(.secondary)
                }

                contextView

                Text(formatCost(session.costUsd))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.caption2)
            .padding(.leading, 13)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 12)
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
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary.opacity(0.06))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(pct >= 60 ? 1.0 : 0.4))
                        .frame(width: geo.size.width * min(pct / 100, 1.0))
                }
            }
            .frame(width: 36, height: 4)

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
