import SwiftUI
import AppKit

extension AgentStatus {
    var color: NSColor {
        switch self {
        case .attention:    return .systemYellow
        case .working:      return .systemBlue
        case .idle:         return .systemGreen
        case .disconnected: return .systemGray
        }
    }

}

/// Renders colored dots with counts for non-zero statuses
func menuBarDotsImage(sessions: [SessionInfo]) -> NSImage {
    let grouped = Dictionary(grouping: sessions) { $0.cachedStatus }

    let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    let dotSize: CGFloat = 6
    let dotTextGap: CGFloat = 1
    let pairGap: CGFloat = 4
    let height: CGFloat = 18
    let textColor: NSColor = .labelColor

    // Only show statuses that have sessions (or always show working/idle for context)
    var segments: [(color: NSColor, text: String, textWidth: CGFloat)] = []
    for status in AgentStatus.displayOrder {
        let count = grouped[status]?.count ?? 0
        // Always show attention if > 0, always show working/idle, skip disconnected if 0
        if count == 0 && (status == .attention || status == .disconnected) { continue }
        let text = "\(count)"
        let textWidth = (text as NSString).size(withAttributes: [.font: font]).width
        segments.append((status.color, text, textWidth))
    }

    if segments.isEmpty {
        return singleDotImage(color: .systemGray)
    }

    let totalWidth = segments.reduce(CGFloat(0)) { acc, seg in
        acc + dotSize + dotTextGap + seg.textWidth
    } + CGFloat(segments.count - 1) * pairGap

    let image = NSImage(size: NSSize(width: totalWidth, height: height), flipped: false) { _ in
        var x: CGFloat = 0
        for seg in segments {
            let dotY = (height - dotSize) / 2
            seg.color.setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: dotY, width: dotSize, height: dotSize)).fill()
            x += dotSize + dotTextGap

            let textSize = (seg.text as NSString).size(withAttributes: [.font: font])
            let textY = (height - textSize.height) / 2
            (seg.text as NSString).draw(
                at: NSPoint(x: x, y: textY),
                withAttributes: [.font: font, .foregroundColor: textColor]
            )
            x += seg.textWidth + pairGap
        }
        return true
    }
    image.isTemplate = false
    return image
}

private func singleDotImage(color: NSColor) -> NSImage {
    let size: CGFloat = 8
    let height: CGFloat = 18
    let image = NSImage(size: NSSize(width: size, height: height), flipped: false) { _ in
        let y = (height - size) / 2
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 0, y: y, width: size, height: size)).fill()
        return true
    }
    image.isTemplate = false
    return image
}
