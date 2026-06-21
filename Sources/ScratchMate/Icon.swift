import AppKit

/// "Caret" brand artwork. The glyph is `[::` : a bracket that opens and never
/// closes (Antinote's ephemeral field) embracing `::` (TextMate's command trigger).
enum AppIcon {
    /// Monochrome glyph for the menu bar. isTemplate=true: macOS tints it itself
    /// for light/dark. Drawn in bottom-left coords (non-flipped NSImage).
    static func menuBar() -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat = 0.7) {
                NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r).fill()
            }
            // bracket `[`: stem + two arms, opens to the right, never closes.
            rr(2.4, 3.0, 1.7, 12.0)    // vertical stem
            rr(2.4, 13.3, 4.2, 1.7)    // top arm
            rr(2.4, 3.0, 4.2, 1.7)     // bottom arm
            // `::`: four dots in a 2x2 grid.
            let d: CGFloat = 2.3
            for (x, y) in [(8.7, 10.0), (8.7, 5.0), (12.5, 10.0), (12.5, 5.0)] as [(CGFloat, CGFloat)] {
                rr(x, y, d, d, 0.8)
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}
