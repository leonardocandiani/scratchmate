import AppKit

/// Floating palette-style panel. Non-activating, stays above other windows and
/// disappears when it loses focus (hide on blur), in the spirit of Antinote.
final class ScratchPanel: NSPanel {
    var onResignKey: (() -> Void)?

    init(contentViewController: NSViewController) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.contentViewController = contentViewController
        self.isFloatingPanel = true
        self.level = .floating
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        // Transparent, so the editor's glass (NSVisualEffectView) shows through.
        self.isOpaque = false
        self.backgroundColor = .clear
        self.isMovableByWindowBackground = true
        self.hidesOnDeactivate = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isReleasedWhenClosed = false
        self.delegate = self
    }

    // A titlebar-less panel needs this to accept keyboard focus.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Centers and brings to front, stealing keyboard focus.
    func toggle() {
        if isVisible {
            orderOut(nil)
        } else {
            center()
            makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func show() {
        center()
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension ScratchPanel: NSWindowDelegate {
    func windowDidResignKey(_ notification: Notification) {
        onResignKey?()
    }
}
