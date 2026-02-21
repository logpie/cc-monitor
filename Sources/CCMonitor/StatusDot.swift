import SwiftUI
import AppKit

extension AgentStatus {
    var color: NSColor {
        switch self {
        case .attention:    return .systemOrange
        case .working:      return .systemBlue
        case .idle:         return .systemGreen
        case .disconnected: return .systemGray
        }
    }
}

/// Renders pill-shaped status badges in the menu bar
func menuBarDotsImage(sessions: [SessionInfo], flashAttention: Bool = false) -> NSImage {
    let grouped = Dictionary(grouping: sessions) { $0.cachedStatus }

    let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .bold)
    let pillHeight: CGFloat = 14
    let pillPadH: CGFloat = 5
    let pillGap: CGFloat = 3
    let height: CGFloat = 18

    struct Pill {
        let color: NSColor
        let text: String
        let width: CGFloat
        let dimmed: Bool
    }

    var pills: [Pill] = []
    for status in AgentStatus.displayOrder {
        let count = grouped[status]?.count ?? 0
        if count == 0 && (status == .attention || status == .disconnected) { continue }

        let text = status == .attention ? "!" : "\(count)"
        let textWidth = (text as NSString).size(withAttributes: [.font: font]).width
        let pillWidth = textWidth + pillPadH * 2

        let dimmed = status == .attention && flashAttention
        pills.append(Pill(color: status.color, text: text, width: pillWidth, dimmed: dimmed))
    }

    if pills.isEmpty {
        return singlePillImage()
    }

    let totalWidth = pills.reduce(CGFloat(0)) { $0 + $1.width }
        + CGFloat(pills.count - 1) * pillGap

    let image = NSImage(size: NSSize(width: totalWidth, height: height), flipped: false) { _ in
        var x: CGFloat = 0
        for pill in pills {
            let y = (height - pillHeight) / 2
            let rect = NSRect(x: x, y: y, width: pill.width, height: pillHeight)
            let path = NSBezierPath(roundedRect: rect, xRadius: pillHeight / 2, yRadius: pillHeight / 2)

            if pill.dimmed {
                pill.color.withAlphaComponent(0.25).setFill()
            } else {
                pill.color.withAlphaComponent(0.85).setFill()
            }
            path.fill()

            let textColor: NSColor = pill.dimmed ? .white.withAlphaComponent(0.4) : .white
            let textSize = (pill.text as NSString).size(withAttributes: [.font: font])
            let textX = x + (pill.width - textSize.width) / 2
            let textY = y + (pillHeight - textSize.height) / 2
            (pill.text as NSString).draw(
                at: NSPoint(x: textX, y: textY),
                withAttributes: [.font: font, .foregroundColor: textColor]
            )

            x += pill.width + pillGap
        }
        return true
    }
    image.isTemplate = false
    return image
}

private func singlePillImage() -> NSImage {
    let height: CGFloat = 18
    let dotSize: CGFloat = 8
    let image = NSImage(size: NSSize(width: dotSize, height: height), flipped: false) { _ in
        let y = (height - dotSize) / 2
        NSColor.systemGray.withAlphaComponent(0.5).setFill()
        NSBezierPath(ovalIn: NSRect(x: 0, y: y, width: dotSize, height: dotSize)).fill()
        return true
    }
    image.isTemplate = false
    return image
}
