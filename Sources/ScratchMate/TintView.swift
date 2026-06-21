import AppKit

/// Theme-color layer that sits between the glass blur and the editor. It carries the
/// transparency tint (background color at the configured opacity).
///
/// Why a custom layer-backed view instead of a plain NSView: setting
/// `view.appearance` on the container makes AppKit rebuild the backing CALayer of its
/// subviews asynchronously, which discards any `layer.backgroundColor` set imperatively.
/// A plain NSView has no `updateLayer`, so the tint color would silently vanish on every
/// theme switch. By owning `updateLayer`, AppKit asks us for the color again whenever it
/// rebuilds the layer, so the tint survives appearance changes.
final class TintView: NSView {
    /// Fill color drawn behind the editor. Setting it marks the view for redisplay so
    /// `updateLayer()` reapplies it on the next draw pass.
    var fillColor: NSColor = .clear {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    /// Drive the backing layer through `updateLayer` so AppKit reapplies the fill after
    /// it rebuilds the layer (on appearance changes), instead of drawing in `draw(_:)`.
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = fillColor.cgColor
    }
}
