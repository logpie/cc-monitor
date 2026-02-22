import SwiftUI
import AppKit

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

struct SessionRowView: View {
    let session: SessionInfo
    let theme: ColorTheme
    @State private var isHovered = false

    private var status: AgentStatus { session.cachedStatus }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Row 1: dot + name + path + time
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(nsColor: status.color(for: theme)))
                    .frame(width: 7, height: 7)

                Text(session.displayLabel)
                    .font(.system(.callout, weight: .medium))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)

                Text(session.displayPath)
                    .font(.caption2)
                    .foregroundStyle(theme.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.head)

                Spacer(minLength: 4)

                Text(session.relativeTime)
                    .font(.caption2)
                    .foregroundStyle(theme.secondaryText)
                    .monospacedDigit()
                    .frame(minWidth: 28, alignment: .trailing)
            }

            // Row 2: branch + git status
            if !session.gitBranch.isEmpty {
                HStack(spacing: 6) {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 8))
                            .foregroundStyle(theme.accent)
                        Text(session.gitBranch)
                            .foregroundStyle(theme.secondaryText)
                    }
                    .lineLimit(1)

                    if (session.gitStaged ?? 0) > 0 {
                        Text("+\(session.gitStaged!)")
                            .foregroundStyle(theme.gitStaged)
                            .monospacedDigit()
                    }
                    if (session.gitDirty ?? 0) > 0 {
                        Text("~\(session.gitDirty!)")
                            .foregroundStyle(theme.gitDirty)
                            .monospacedDigit()
                    }
                    if (session.gitUntracked ?? 0) > 0 {
                        Text("?\(session.gitUntracked!)")
                            .foregroundStyle(theme.gitUntracked)
                            .monospacedDigit()
                    }
                }
                .font(.caption2)
                .padding(.leading, 13)
            }

            // Row 3: active subagents
            if !session.activeAgents.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "circle.grid.2x2")
                        .font(.system(size: 9))
                        .foregroundStyle(theme.accent)
                    let types = session.activeAgents.map(\.type).joined(separator: ", ")
                    let count = session.activeAgents.count
                    Text("\(count) agent\(count == 1 ? "" : "s"): \(types)")
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.caption2)
                .foregroundStyle(theme.secondaryText)
                .padding(.leading, 13)
            }

            // Row 4: task context (persists across state changes)
            if let context = session.hookContext, !context.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: contextIcon(for: context))
                        .font(.system(size: 9))
                        .foregroundStyle(theme.accent)
                    Text(context)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.caption2)
                .foregroundStyle(theme.secondaryText)
                .padding(.leading, 13)
            }

            // Row 5: last response from Claude
            if let msg = session.lastMessage, !msg.isEmpty {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 7))
                        .foregroundStyle(theme.accent.opacity(0.5))
                        .padding(.top, 2)
                    Text(msg)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
                .font(.caption2)
                .foregroundStyle(theme.tertiaryText)
                .padding(.leading, 13)
            }

            // Row 6: model + context bar + cost (always last)
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "cpu")
                        .font(.system(size: 9))
                        .foregroundStyle(theme.accent)
                    Text(session.model)
                        .foregroundStyle(theme.secondaryText)
                }

                contextView

                Text(formatCost(session.costUsd))
                    .monospacedDigit()
                    .foregroundStyle(theme.secondaryText)
            }
            .font(.caption2)
            .padding(.leading, 13)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? theme.cardHover : theme.cardBackground)
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
        let barColor: Color = pct >= 85
            ? theme.contextCritical
            : pct >= 60
                ? theme.contextWarning
                : theme.contextHealthy
        let textColor: Color = pct >= 85
            ? theme.contextCritical
            : pct >= 60
                ? theme.contextWarning
                : theme.secondaryText

        HStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(theme.primaryText.opacity(0.08))
                    Capsule()
                        .fill(barColor.opacity(0.85))
                        .frame(width: geo.size.width * min(pct / 100, 1.0))
                }
            }
            .frame(width: 40, height: 4)

            Text("\(Int(pct))%")
                .monospacedDigit()
                .foregroundStyle(textColor)
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
