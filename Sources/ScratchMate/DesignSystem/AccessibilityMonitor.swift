import AppKit

/// Watches the system accessibility display options and exposes the three that
/// affect ScratchMate's chrome: Reduce Transparency, Reduce Motion, and
/// Increase Contrast. Chrome surfaces read these to raise glass opacity, skip
/// animations, or thicken borders.
///
/// The monitor subscribes to NSWorkspace's
/// `accessibilityDisplayOptionsDidChangeNotification` and fires `onChange` when
/// any option flips, so callers can refresh their appearance without polling.
/// Each property reads NSWorkspace live, so the values are always current even
/// before the first notification.
final class AccessibilityMonitor {

    /// Called on the main thread whenever any tracked accessibility option
    /// changes. Set this to re-evaluate chrome appearance.
    var onChange: (() -> Void)?

    /// True when the user asked to reduce transparency: chrome should lean on
    /// opaque fills instead of glass blur.
    var reduceTransparency: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    /// True when the user asked to reduce motion: chrome should skip or shorten
    /// animations.
    var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// True when the user asked to increase contrast: chrome should thicken
    /// borders and deepen separators.
    var increaseContrast: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(displayOptionsDidChange(_:)),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    /// ObjC notification entry point. The selector is delivered nonisolated, so
    /// we hop back onto the main actor before touching `onChange` (the workspace
    /// posts this notification on the main thread).
    @objc
    nonisolated private func displayOptionsDidChange(_ note: Notification) {
        MainActor.assumeIsolated {
            onChange?()
        }
    }
}
