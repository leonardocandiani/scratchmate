import AppKit

/// Type scale for ScratchMate. Two families:
///
///  - Chrome UI text uses the system font through `NSFont.preferredFont`, so it
///    tracks the user's text-size and Dynamic Type settings automatically.
///  - The editor and counters use monospaced system fonts: a true monospace for
///    the writing surface, and a monospaced-digit variant for counters so the
///    numbers do not jitter as they change.
///
/// Symbol glyphs go through `symbolConfig` so every SF Symbol in the chrome
/// shares one rendering treatment (hierarchical by default, palette when a
/// surface needs an explicit secondary color such as the accent).
enum Typography {

    // MARK: - Chrome UI text (system, Dynamic Type aware)

    /// Body text for chrome labels and controls.
    static func body() -> NSFont { .preferredFont(forTextStyle: .body) }

    /// Prominent chrome titles (panel headers, onboarding steps).
    static func title2() -> NSFont { .preferredFont(forTextStyle: .title2) }

    /// Section headlines and emphasized rows.
    static func headline() -> NSFont { .preferredFont(forTextStyle: .headline) }

    /// Captions, footnotes, and faint metadata.
    static func caption() -> NSFont { .preferredFont(forTextStyle: .caption1) }

    // MARK: - Editor and counters (monospaced)

    /// The writing-surface font: true monospace so code and prose align.
    static func editorFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        .monospacedSystemFont(ofSize: size, weight: weight)
    }

    /// Counter font: monospaced digits over the proportional system font, so
    /// word/character counts stay fixed-width as the value changes.
    static func counterFont(size: CGFloat, weight: NSFont.Weight = .medium) -> NSFont {
        .monospacedDigitSystemFont(ofSize: size, weight: weight)
    }

    // MARK: - Symbol glyphs

    /// A hierarchical SF Symbol configuration (one color, depth via opacity).
    /// The default treatment for monochrome chrome glyphs.
    static func symbolConfig(pointSize: CGFloat, weight: NSFont.Weight = .regular) -> NSImage.SymbolConfiguration {
        NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
            .applying(.preferringHierarchical())
    }

    /// A palette SF Symbol configuration with explicit colors. Use when a glyph
    /// needs the accent (or any two-tone treatment), for example the caret mark.
    static func symbolConfig(pointSize: CGFloat, weight: NSFont.Weight = .regular, colors: [NSColor]) -> NSImage.SymbolConfiguration {
        NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
            .applying(NSImage.SymbolConfiguration(paletteColors: colors))
    }
}
