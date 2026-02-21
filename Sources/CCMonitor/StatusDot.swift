import SwiftUI
import AppKit

extension AgentStatus {
    var color: NSColor {
        switch self {
        case .working:  return .systemYellow
        case .waiting:  return .systemRed
        case .idle:     return .systemGreen
        case .error:    return .systemRed
        }
    }
}

/// Renders colored dots as an NSImage for the menu bar (isTemplate=false to preserve colors)
func menuBarDotsImage(sessions: [SessionInfo]) -> NSImage {
    let dotSize: CGFloat = 8
    let spacing: CGFloat = 4
    let count = max(sessions.count, 1)
    let totalWidth = CGFloat(count) * dotSize + CGFloat(count - 1) * spacing
    let height: CGFloat = 18

    let image = NSImage(size: NSSize(width: totalWidth, height: height), flipped: false) { rect in
        for (i, session) in sessions.enumerated() {
            let x = CGFloat(i) * (dotSize + spacing)
            let y = (height - dotSize) / 2
            let dotRect = NSRect(x: x, y: y, width: dotSize, height: dotSize)
            let color = session.status().color
            color.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
        }
        if sessions.isEmpty {
            let x: CGFloat = 0
            let y = (height - dotSize) / 2
            NSColor.systemGray.setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: y, width: dotSize, height: dotSize)).fill()
        }
        return true
    }
    image.isTemplate = false
    return image
}
