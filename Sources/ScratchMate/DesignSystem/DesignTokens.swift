import AppKit

/// Central color vocabulary for ScratchMate's chrome (toolbars, panels, dock,
/// overlays). Two layers live here:
///
///  - The "Caret" accent (amber #FFB454), the single brand color reserved for
///    the caret, selection highlight, and the primary action. Everything else
///    in the chrome stays neutral so the accent reads as a real accent.
///  - Semantic, appearance-adaptive colors built on AppKit's dynamic system
///    colors (labelColor, separatorColor, etc). Exposing them through one enum
///    keeps every chrome surface reading from the same palette instead of
///    hard-coding NSColor calls scattered across view controllers.
///
/// Note: Theme.swift already declares a global `NSColor(hex:)` convenience
/// initializer. We do not redeclare it here; the private `color(hex:)` helper
/// below is the enum's own converter for the literal accent value.
enum DesignTokens {

    // MARK: - Brand accent

    /// The "Caret" amber accent (#FFB454). The only chromatic color in the
    /// chrome. Use it for the caret, selection, focus rings, and the single
    /// primary action, never as a generic fill.
    static var accent: NSColor { color(hex: 0xFFB454) }

    /// A muted wash of the accent for tinting glass surfaces (alpha 0.22 sits in
    /// the 0.2-0.3 range Apple recommends so glass reads as tinted, not painted).
    static var accentTint: NSColor { accent.withAlphaComponent(0.22) }

    // MARK: - Adaptive semantic colors (chrome)

    /// Primary chrome text. Adapts to light/dark automatically.
    static var label: NSColor { .labelColor }

    /// Secondary chrome text (subtitles, inactive captions).
    static var secondaryLabel: NSColor { .secondaryLabelColor }

    /// Tertiary chrome text (placeholders, faint metadata).
    static var tertiaryLabel: NSColor { .tertiaryLabelColor }

    /// Hairline separators between chrome regions.
    static var separator: NSColor { .separatorColor }

    /// Opaque window background, for non-glass chrome backings.
    static var windowBackground: NSColor { .windowBackgroundColor }

    // MARK: - Adaptive helpers

    /// Builds an appearance-adaptive color that resolves to `dark` under
    /// darkAqua and `light` otherwise. Use for custom chrome fills that have no
    /// matching system color (subtle white/black washes on glass, hover pads).
    ///
    ///     DesignTokens.adaptive(name: "hoverPad",
    ///         light: NSColor.black.withAlphaComponent(0.06),
    ///         dark: NSColor.white.withAlphaComponent(0.10))
    static func adaptive(name: NSColor.Name, light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: name) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    // MARK: - Internal hex converter

    /// Converts a packed 0xRRGGBB integer to an sRGB NSColor. Internal to the
    /// enum so we do not collide with Theme.swift's global `NSColor(hex:)`.
    private static func color(hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
