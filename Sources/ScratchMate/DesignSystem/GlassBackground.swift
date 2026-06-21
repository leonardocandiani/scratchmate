import AppKit

/// Single gate for Liquid Glass across ScratchMate's chrome. Every floating
/// surface (the editor backing, panels, popovers) asks here for its backing so
/// the whole app speaks one glass language:
///
///  - macOS 26+ gets real glass (NSGlassEffectView) with a continuous corner
///    radius and an optional accent tint at alpha 0.2-0.3.
///  - macOS 14/15 fall back to NSVisualEffectView with the HUD material. The
///    `#available` gate is mandatory: NSGlassEffectView does not exist before
///    macOS 26, so an ungated reference crashes on the deployment target (14).
///
/// Deployment target stays macOS 14. Real glass self-rims, so the fallback adds
/// a faint hairline only on rounded shapes to give the blur a defined edge.
enum GlassBackground {

    /// Corner-radius scale shared by every glass surface, so radii stay
    /// consistent and concentric across the chrome.
    enum Radius {
        static let panel: CGFloat = 16
        static let card: CGFloat = 12
        static let control: CGFloat = 11
        static let pill: CGFloat = 6
    }

    /// A full-bleed backing view meant to sit behind the editor content as the
    /// back layer of a borderless panel. Edge-to-edge (no corner radius), set to
    /// autoresize so it fills its superview; the caller stacks controls above it.
    static func backing() -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = 0
            glass.autoresizingMask = [.width, .height]
            return glass
        }
        let blur = makeBlur(material: .hudWindow, cornerRadius: 0, tint: nil)
        blur.autoresizingMask = [.width, .height]
        return blur
    }

    /// A standalone glass (or blur) capsule for a floating panel/card/popover.
    /// Pass an accent `tint` only on the single primary surface; leave it nil for
    /// neutral chrome so glass stays untinted, as Apple recommends.
    static func panel(cornerRadius: CGFloat = Radius.panel, tint: NSColor? = nil) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            if let tint { glass.tintColor = tint }
            return glass
        }
        return makeBlur(material: .hudWindow, cornerRadius: cornerRadius, tint: tint)
    }

    /// Wraps `content` in a glass panel and returns the backing view to install in
    /// the hierarchy. On macOS 26 the content goes into the glass view's
    /// `contentView` (Apple's documented pattern, so the material composes under it);
    /// on the fallback it is pinned over the blur. The content is edge-to-edge.
    static func panel(wrapping content: NSView, cornerRadius: CGFloat = Radius.panel, tint: NSColor? = nil) -> NSView {
        content.translatesAutoresizingMaskIntoConstraints = false
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            if let tint { glass.tintColor = tint }
            glass.contentView = content
            return glass
        }
        let blur = makeBlur(material: .hudWindow, cornerRadius: cornerRadius, tint: tint)
        blur.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: blur.topAnchor),
            content.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
        ])
        return blur
    }

    /// A chrome bar backing (footer/toolbar). On macOS 26 it is real glass so the
    /// whole window speaks one glass language; on the fallback it is a within-window
    /// header material that samples the editor content sitting behind it.
    static func chromeBar() -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = 0
            return glass
        }
        let blur = NSVisualEffectView()
        blur.material = .headerView
        blur.blendingMode = .withinWindow
        blur.state = .active
        return blur
    }

    // MARK: - Fallback (pre-macOS 26)

    /// Builds the NSVisualEffectView blur used on macOS 14/15. `.behindWindow`
    /// blending and `.active` state keep the material live regardless of window
    /// key state, matching the always-on feel of real glass.
    private static func makeBlur(material: NSVisualEffectView.Material, cornerRadius: CGFloat, tint: NSColor?) -> NSVisualEffectView {
        let blur = NSVisualEffectView()
        blur.material = material
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = cornerRadius
        blur.layer?.cornerCurve = .continuous
        blur.layer?.masksToBounds = true

        // The hairline is fallback-only (real glass draws its own rim) and also
        // serves as the accessibility contrast edge. An edge-to-edge backing
        // (cornerRadius 0) skips it so it never frames the whole surface with a
        // stray white border.
        if cornerRadius > 0 {
            let ws = NSWorkspace.shared
            let highContrast = ws.accessibilityDisplayShouldIncreaseContrast
            let lessTransparent = ws.accessibilityDisplayShouldReduceTransparency
            let borderAlpha: CGFloat = highContrast ? 0.55 : (lessTransparent ? 0.30 : 0.18)
            blur.layer?.borderWidth = highContrast ? 1.5 : 1
            blur.layer?.borderColor = NSColor.white.withAlphaComponent(borderAlpha).cgColor
        }

        // Tinted fallback: wash the accent over the blur at low alpha so the
        // primary surface still reads as tinted without real glass.
        if let tint {
            let wash = CALayer()
            wash.frame = blur.bounds
            wash.backgroundColor = tint.withAlphaComponent(0.22).cgColor
            wash.cornerRadius = cornerRadius
            wash.cornerCurve = .continuous
            wash.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            blur.layer?.addSublayer(wash)
        }
        return blur
    }
}
