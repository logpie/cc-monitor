import SwiftUI
import AppKit

enum ColorTheme: String, CaseIterable {
    case dracula, tokyoNight, oneDark, catppuccin, gruvbox, nord, solarized, monokai, macOSNative

    var displayName: String {
        switch self {
        case .dracula:     return "Dracula"
        case .tokyoNight:  return "Tokyo Night"
        case .oneDark:     return "One Dark"
        case .catppuccin:  return "Catppuccin"
        case .gruvbox:     return "Gruvbox"
        case .nord:        return "Nord"
        case .solarized:   return "Solarized"
        case .monokai:     return "Monokai"
        case .macOSNative: return "macOS Native"
        }
    }

    // MARK: - Panel / surface colors

    func panelBackground(opacity: Double = 0.82) -> Color {
        switch self {
        case .dracula:     return Color(hex: 0x282a36).opacity(opacity)
        case .tokyoNight:  return Color(hex: 0x1a1b26).opacity(opacity)
        case .oneDark:     return Color(hex: 0x282c34).opacity(opacity)
        case .catppuccin:  return Color(hex: 0x1e1e2e).opacity(opacity)
        case .gruvbox:     return Color(hex: 0x282828).opacity(opacity)
        case .nord:        return Color(hex: 0x2e3440).opacity(opacity)
        case .solarized:   return Color(hex: 0x002b36).opacity(opacity)
        case .monokai:     return Color(hex: 0x272822).opacity(opacity)
        case .macOSNative: return Color(nsColor: .windowBackgroundColor).opacity(opacity)
        }
    }

    var cardBackground: Color {
        switch self {
        case .dracula:     return Color(hex: 0x44475a).opacity(0.4)
        case .tokyoNight:  return Color(hex: 0x292e42).opacity(0.5)
        case .oneDark:     return Color(hex: 0x2c313c).opacity(0.5)
        case .catppuccin:  return Color(hex: 0x313244).opacity(0.5)
        case .gruvbox:     return Color(hex: 0x3c3836).opacity(0.5)
        case .nord:        return Color(hex: 0x3b4252).opacity(0.5)
        case .solarized:   return Color(hex: 0x073642).opacity(0.5)
        case .monokai:     return Color(hex: 0x3e3d32).opacity(0.5)
        case .macOSNative: return Color.primary.opacity(0.06)
        }
    }

    var cardHover: Color {
        switch self {
        case .dracula:     return Color(hex: 0x44475a).opacity(0.7)
        case .tokyoNight:  return Color(hex: 0x292e42).opacity(0.8)
        case .oneDark:     return Color(hex: 0x2c313c).opacity(0.8)
        case .catppuccin:  return Color(hex: 0x313244).opacity(0.8)
        case .gruvbox:     return Color(hex: 0x3c3836).opacity(0.8)
        case .nord:        return Color(hex: 0x3b4252).opacity(0.8)
        case .solarized:   return Color(hex: 0x073642).opacity(0.8)
        case .monokai:     return Color(hex: 0x3e3d32).opacity(0.8)
        case .macOSNative: return Color.primary.opacity(0.12)
        }
    }

    var dividerColor: Color {
        switch self {
        case .dracula:     return Color(hex: 0x6272a4).opacity(0.3)
        case .tokyoNight:  return Color(hex: 0x565f89).opacity(0.3)
        case .oneDark:     return Color(hex: 0x5c6370).opacity(0.3)
        case .catppuccin:  return Color(hex: 0x6c7086).opacity(0.3)
        case .gruvbox:     return Color(hex: 0xa89984).opacity(0.3)
        case .nord:        return Color(hex: 0x4c566a).opacity(0.3)
        case .solarized:   return Color(hex: 0x586e75).opacity(0.3)
        case .monokai:     return Color(hex: 0x75715e).opacity(0.3)
        case .macOSNative: return Color(nsColor: .separatorColor)
        }
    }

    // MARK: - Text colors

    var primaryText: Color {
        switch self {
        case .dracula:     return Color(hex: 0xf8f8f2)
        case .tokyoNight:  return Color(hex: 0xc0caf5)
        case .oneDark:     return Color(hex: 0xabb2bf)
        case .catppuccin:  return Color(hex: 0xcdd6f4)
        case .gruvbox:     return Color(hex: 0xebdbb2)
        case .nord:        return Color(hex: 0xeceff4)
        case .solarized:   return Color(hex: 0x839496)
        case .monokai:     return Color(hex: 0xf8f8f2)
        case .macOSNative: return Color(nsColor: .labelColor)
        }
    }

    var secondaryText: Color {
        switch self {
        case .macOSNative: return Color(nsColor: .secondaryLabelColor)
        default:           return primaryText.opacity(0.6)
        }
    }

    var tertiaryText: Color {
        switch self {
        case .dracula:     return Color(hex: 0x6272a4)
        case .tokyoNight:  return Color(hex: 0x565f89)
        case .oneDark:     return Color(hex: 0x5c6370)
        case .catppuccin:  return Color(hex: 0x6c7086)
        case .gruvbox:     return Color(hex: 0xa89984)
        case .nord:        return Color(hex: 0x4c566a)
        case .solarized:   return Color(hex: 0x586e75)
        case .monokai:     return Color(hex: 0x75715e)
        case .macOSNative: return Color(nsColor: .tertiaryLabelColor)
        }
    }

    // MARK: - Accent (icons, tints)

    var accent: Color {
        switch self {
        case .dracula:     return Color(hex: 0x8be9fd)   // cyan
        case .tokyoNight:  return Color(hex: 0x7aa2f7)   // blue
        case .oneDark:     return Color(hex: 0x61afef)    // blue
        case .catppuccin:  return Color(hex: 0x89dceb)    // sky
        case .gruvbox:     return Color(hex: 0x8ec07c)    // aqua
        case .nord:        return Color(hex: 0x88c0d0)    // frost
        case .solarized:   return Color(hex: 0x2aa198)    // cyan
        case .monokai:     return Color(hex: 0x66d9ef)    // blue
        case .macOSNative: return Color(nsColor: .secondaryLabelColor)
        }
    }

    // MARK: - Status colors (NSColor for menu bar rendering)

    var attentionColor: NSColor {
        switch self {
        case .dracula:     return NSColor(red: 1.0, green: 0.72, blue: 0.42, alpha: 1)      // #ffb86c
        case .tokyoNight:  return NSColor(red: 0.878, green: 0.686, blue: 0.408, alpha: 1)   // #e0af68
        case .oneDark:     return NSColor(red: 0.820, green: 0.604, blue: 0.400, alpha: 1)   // #d19a66
        case .catppuccin:  return NSColor(red: 0.980, green: 0.702, blue: 0.529, alpha: 1)   // #fab387
        case .gruvbox:     return NSColor(red: 0.996, green: 0.502, blue: 0.098, alpha: 1)   // #fe8019
        case .nord:        return NSColor(red: 0.816, green: 0.529, blue: 0.439, alpha: 1)   // #d08770
        case .solarized:   return NSColor(red: 0.796, green: 0.294, blue: 0.086, alpha: 1)   // #cb4b16
        case .monokai:     return NSColor(red: 0.992, green: 0.592, blue: 0.122, alpha: 1)   // #fd971f
        case .macOSNative: return .systemOrange
        }
    }

    var workingColor: NSColor {
        switch self {
        case .dracula:     return NSColor(red: 0.74, green: 0.58, blue: 0.98, alpha: 1)      // #bd93f9
        case .tokyoNight:  return NSColor(red: 0.478, green: 0.635, blue: 0.969, alpha: 1)   // #7aa2f7
        case .oneDark:     return NSColor(red: 0.380, green: 0.686, blue: 0.937, alpha: 1)   // #61afef
        case .catppuccin:  return NSColor(red: 0.537, green: 0.706, blue: 0.980, alpha: 1)   // #89b4fa
        case .gruvbox:     return NSColor(red: 0.514, green: 0.647, blue: 0.596, alpha: 1)   // #83a598
        case .nord:        return NSColor(red: 0.506, green: 0.631, blue: 0.757, alpha: 1)   // #81a1c1
        case .solarized:   return NSColor(red: 0.149, green: 0.545, blue: 0.824, alpha: 1)   // #268bd2
        case .monokai:     return NSColor(red: 0.400, green: 0.851, blue: 0.937, alpha: 1)   // #66d9ef
        case .macOSNative: return .systemBlue
        }
    }

    var idleColor: NSColor {
        switch self {
        case .dracula:     return NSColor(red: 0.31, green: 0.98, blue: 0.48, alpha: 1)      // #50fa7b
        case .tokyoNight:  return NSColor(red: 0.620, green: 0.808, blue: 0.416, alpha: 1)   // #9ece6a
        case .oneDark:     return NSColor(red: 0.596, green: 0.765, blue: 0.475, alpha: 1)   // #98c379
        case .catppuccin:  return NSColor(red: 0.651, green: 0.890, blue: 0.631, alpha: 1)   // #a6e3a1
        case .gruvbox:     return NSColor(red: 0.722, green: 0.733, blue: 0.149, alpha: 1)   // #b8bb26
        case .nord:        return NSColor(red: 0.639, green: 0.745, blue: 0.549, alpha: 1)   // #a3be8c
        case .solarized:   return NSColor(red: 0.522, green: 0.600, blue: 0.0, alpha: 1)     // #859900
        case .monokai:     return NSColor(red: 0.651, green: 0.886, blue: 0.180, alpha: 1)   // #a6e22e
        case .macOSNative: return .systemGreen
        }
    }

    var disconnectedColor: NSColor {
        switch self {
        case .dracula:     return NSColor(red: 0.38, green: 0.45, blue: 0.64, alpha: 1)      // #6272a4
        case .tokyoNight:  return NSColor(red: 0.337, green: 0.373, blue: 0.537, alpha: 1)   // #565f89
        case .oneDark:     return NSColor(red: 0.361, green: 0.388, blue: 0.439, alpha: 1)   // #5c6370
        case .catppuccin:  return NSColor(red: 0.424, green: 0.439, blue: 0.525, alpha: 1)   // #6c7086
        case .gruvbox:     return NSColor(red: 0.659, green: 0.600, blue: 0.518, alpha: 1)   // #a89984
        case .nord:        return NSColor(red: 0.298, green: 0.337, blue: 0.416, alpha: 1)   // #4c566a
        case .solarized:   return NSColor(red: 0.345, green: 0.431, blue: 0.459, alpha: 1)   // #586e75
        case .monokai:     return NSColor(red: 0.459, green: 0.443, blue: 0.369, alpha: 1)   // #75715e
        case .macOSNative: return .systemGray
        }
    }

    var flashColor: NSColor {
        switch self {
        case .dracula:     return NSColor(red: 1.0, green: 0.47, blue: 0.78, alpha: 1)       // #ff79c6
        case .tokyoNight:  return NSColor(red: 0.969, green: 0.463, blue: 0.557, alpha: 1)   // #f7768e
        case .oneDark:     return NSColor(red: 0.878, green: 0.424, blue: 0.459, alpha: 1)   // #e06c75
        case .catppuccin:  return NSColor(red: 0.953, green: 0.545, blue: 0.659, alpha: 1)   // #f38ba8
        case .gruvbox:     return NSColor(red: 0.984, green: 0.286, blue: 0.204, alpha: 1)   // #fb4934
        case .nord:        return NSColor(red: 0.749, green: 0.380, blue: 0.416, alpha: 1)   // #bf616a
        case .solarized:   return NSColor(red: 0.827, green: 0.212, blue: 0.510, alpha: 1)   // #d33682
        case .monokai:     return NSColor(red: 0.976, green: 0.149, blue: 0.447, alpha: 1)   // #f92672
        case .macOSNative: return .systemRed
        }
    }

    // MARK: - Git colors (SwiftUI Color)

    var gitStaged: Color {
        switch self {
        case .dracula:     return Color(hex: 0x50fa7b)
        case .tokyoNight:  return Color(hex: 0x9ece6a)
        case .oneDark:     return Color(hex: 0x98c379)
        case .catppuccin:  return Color(hex: 0xa6e3a1)
        case .gruvbox:     return Color(hex: 0xb8bb26)
        case .nord:        return Color(hex: 0xa3be8c)
        case .solarized:   return Color(hex: 0x859900)
        case .monokai:     return Color(hex: 0xa6e22e)
        case .macOSNative: return Color(nsColor: .systemGreen)
        }
    }

    var gitDirty: Color {
        switch self {
        case .dracula:     return Color(hex: 0xffb86c)
        case .tokyoNight:  return Color(hex: 0xe0af68)
        case .oneDark:     return Color(hex: 0xd19a66)
        case .catppuccin:  return Color(hex: 0xfab387)
        case .gruvbox:     return Color(hex: 0xfabd2f)
        case .nord:        return Color(hex: 0xebcb8b)
        case .solarized:   return Color(hex: 0xb58900)
        case .monokai:     return Color(hex: 0xe6db74)
        case .macOSNative: return Color(nsColor: .systemYellow)
        }
    }

    var gitUntracked: Color {
        switch self {
        case .dracula:     return Color(hex: 0xbd93f9)
        case .tokyoNight:  return Color(hex: 0x7aa2f7)
        case .oneDark:     return Color(hex: 0xc678dd)
        case .catppuccin:  return Color(hex: 0xcba6f7)
        case .gruvbox:     return Color(hex: 0xd3869b)
        case .nord:        return Color(hex: 0xb48ead)
        case .solarized:   return Color(hex: 0x6c71c4)
        case .monokai:     return Color(hex: 0xae81ff)
        case .macOSNative: return Color(nsColor: .systemPurple)
        }
    }

    // MARK: - Context bar colors (SwiftUI Color)

    var contextHealthy: Color {
        switch self {
        case .dracula:     return Color(hex: 0x8be9fd)
        case .tokyoNight:  return Color(hex: 0x7aa2f7)
        case .oneDark:     return Color(hex: 0x61afef)
        case .catppuccin:  return Color(hex: 0x89dceb)
        case .gruvbox:     return Color(hex: 0x83a598)
        case .nord:        return Color(hex: 0x88c0d0)
        case .solarized:   return Color(hex: 0x2aa198)
        case .monokai:     return Color(hex: 0x66d9ef)
        case .macOSNative: return Color(nsColor: .systemBlue)
        }
    }

    var contextWarning: Color {
        switch self {
        case .dracula:     return Color(hex: 0xffb86c)
        case .tokyoNight:  return Color(hex: 0xe0af68)
        case .oneDark:     return Color(hex: 0xd19a66)
        case .catppuccin:  return Color(hex: 0xfab387)
        case .gruvbox:     return Color(hex: 0xfabd2f)
        case .nord:        return Color(hex: 0xebcb8b)
        case .solarized:   return Color(hex: 0xb58900)
        case .monokai:     return Color(hex: 0xfd971f)
        case .macOSNative: return Color(nsColor: .systemOrange)
        }
    }

    var contextCritical: Color {
        switch self {
        case .dracula:     return Color(hex: 0xff5555)
        case .tokyoNight:  return Color(hex: 0xf7768e)
        case .oneDark:     return Color(hex: 0xe06c75)
        case .catppuccin:  return Color(hex: 0xf38ba8)
        case .gruvbox:     return Color(hex: 0xfb4934)
        case .nord:        return Color(hex: 0xbf616a)
        case .solarized:   return Color(hex: 0xdc322f)
        case .monokai:     return Color(hex: 0xf92672)
        case .macOSNative: return Color(nsColor: .systemPink)
        }
    }

    // MARK: - Swatch (3 signature colors for theme picker preview)

    var swatch: [Color] {
        switch self {
        case .dracula:     return [Color(hex: 0xbd93f9), Color(hex: 0xff79c6), Color(hex: 0x50fa7b)]  // purple, pink, green
        case .tokyoNight:  return [Color(hex: 0x7aa2f7), Color(hex: 0xf7768e), Color(hex: 0x9ece6a)]  // blue, red, green
        case .oneDark:     return [Color(hex: 0x61afef), Color(hex: 0xe06c75), Color(hex: 0x98c379)]  // blue, red, green
        case .catppuccin:  return [Color(hex: 0xcba6f7), Color(hex: 0xf38ba8), Color(hex: 0xa6e3a1)]  // mauve, red, green
        case .gruvbox:     return [Color(hex: 0xfe8019), Color(hex: 0xfabd2f), Color(hex: 0xb8bb26)]  // orange, yellow, green
        case .nord:        return [Color(hex: 0x88c0d0), Color(hex: 0xbf616a), Color(hex: 0xa3be8c)]  // frost, red, green
        case .solarized:   return [Color(hex: 0x268bd2), Color(hex: 0x2aa198), Color(hex: 0xcb4b16)]  // blue, cyan, orange
        case .monokai:     return [Color(hex: 0xf92672), Color(hex: 0x66d9ef), Color(hex: 0xa6e22e)]  // pink, blue, green
        case .macOSNative: return [Color(nsColor: .systemBlue), Color(nsColor: .systemOrange), Color(nsColor: .systemGreen)]
        }
    }

    // MARK: - Helpers

    func statusColor(for status: AgentStatus) -> NSColor {
        switch status {
        case .attention:    return attentionColor
        case .working:      return workingColor
        case .idle:         return idleColor
        case .disconnected: return disconnectedColor
        }
    }
}
