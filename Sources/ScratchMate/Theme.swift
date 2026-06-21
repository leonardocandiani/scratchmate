import AppKit
import ScratchMateCore

/// A ScratchMate theme: editor and preview colors. The colors are hex so they
/// serve both AppKit (NSColor) and the markdown preview's CSS.
struct Theme: Identifiable, Equatable {
    let id: String
    let name: String
    let isDark: Bool
    let background: String   // editor background
    let foreground: String   // text
    let accent: String       // caret, selection, highlight
    let secondary: String    // secondary text, chrome

    var backgroundColor: NSColor { NSColor(hex: background) }
    var foregroundColor: NSColor { NSColor(hex: foreground) }
    var accentColor: NSColor { NSColor(hex: accent) }
    var secondaryColor: NSColor { NSColor(hex: secondary) }

    /// Palette for the markdown preview, derived from the theme.
    var markdownPalette: MarkdownPalette {
        MarkdownPalette(
            background: background,
            foreground: foreground,
            accent: accent,
            secondary: secondary,
            codeBackground: isDark ? background.lightened(0.06) : background.darkened(0.05),
            border: isDark ? foreground.withCSSAlpha(0.18) : foreground.withCSSAlpha(0.14),
            isDark: isDark
        )
    }
}

extension Theme {
    /// Theme catalog. The default is the first; refined by the design spec.
    static let all: [Theme] = [
        // Canonical "Caret" theme: cool graphite + amber (the brand identity).
        Theme(id: "scratch-dark", name: "Caret", isDark: true,
              background: "#15171C", foreground: "#E6E8EC", accent: "#FFB454", secondary: "#8B92A0"),
        Theme(id: "dracula", name: "Dracula", isDark: true,
              background: "#282A36", foreground: "#F8F8F2", accent: "#BD93F9", secondary: "#6272A4"),
        Theme(id: "nord", name: "Nord", isDark: true,
              background: "#2E3440", foreground: "#D8DEE9", accent: "#88C0D0", secondary: "#4C566A"),
        Theme(id: "tokyo-night", name: "Tokyo Night", isDark: true,
              background: "#1A1B26", foreground: "#C0CAF5", accent: "#7AA2F7", secondary: "#565F89"),
        Theme(id: "gruvbox", name: "Gruvbox Dark", isDark: true,
              background: "#282828", foreground: "#EBDBB2", accent: "#FE8019", secondary: "#928374"),
        Theme(id: "solarized", name: "Solarized Dark", isDark: true,
              background: "#002B36", foreground: "#93A1A1", accent: "#268BD2", secondary: "#586E75"),
        Theme(id: "rose-pine", name: "Rosé Pine", isDark: true,
              background: "#191724", foreground: "#E0DEF4", accent: "#C4A7E7", secondary: "#6E6A86"),
        Theme(id: "paper", name: "Paper", isDark: false,
              background: "#FAFAF8", foreground: "#1D1D1F", accent: "#2563EB", secondary: "#6B7280"),
    ]

    static func byID(_ id: String) -> Theme {
        all.first { $0.id == id } ?? all[0]
    }
}

extension NSColor {
    /// Builds an NSColor from "#RRGGBB" (or "#RRGGBBAA"). Defaults to opaque black.
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r, g, b, a: CGFloat
        if s.count == 8 {
            r = CGFloat((value >> 24) & 0xFF) / 255
            g = CGFloat((value >> 16) & 0xFF) / 255
            b = CGFloat((value >> 8) & 0xFF) / 255
            a = CGFloat(value & 0xFF) / 255
        } else {
            r = CGFloat((value >> 16) & 0xFF) / 255
            g = CGFloat((value >> 8) & 0xFF) / 255
            b = CGFloat(value & 0xFF) / 255
            a = 1
        }
        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }
}

private extension String {
    /// Lightens a hex by mixing it with white (factor 0..1). Used for the preview.
    func lightened(_ factor: CGFloat) -> String {
        NSColor(hex: self).blended(withFraction: factor, of: .white)?.toHex() ?? self
    }
    func darkened(_ factor: CGFloat) -> String {
        NSColor(hex: self).blended(withFraction: factor, of: .black)?.toHex() ?? self
    }
    /// Converts a hex to CSS rgba() with alpha.
    func withCSSAlpha(_ alpha: CGFloat) -> String {
        let c = NSColor(hex: self).usingColorSpace(.sRGB) ?? .gray
        return "rgba(\(Int(c.redComponent*255)),\(Int(c.greenComponent*255)),\(Int(c.blueComponent*255)),\(alpha))"
    }
}

private extension NSColor {
    func toHex() -> String {
        let c = usingColorSpace(.sRGB) ?? self
        return String(format: "#%02X%02X%02X",
                      Int(c.redComponent*255), Int(c.greenComponent*255), Int(c.blueComponent*255))
    }
}
