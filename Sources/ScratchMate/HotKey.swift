import AppKit
import Carbon.HIToolbox

/// Global hotkey via Carbon RegisterEventHotKey. It does not require the
/// Accessibility permission (unlike NSEvent.addGlobalMonitor), so the
/// "press and it opens" flow works with no system prompt.
///
/// The class lives outside the main actor (it wraps plain C); only the callback
/// hops back onto the main actor to touch the UI.
///
/// The active combination is read from `Settings` (a virtual key code plus
/// NSEvent.ModifierFlags raw value, the same shape the recorder writes). Call
/// `reload()` after the user rebinds to unregister and register the new combo.
nonisolated final class HotKey: @unchecked Sendable {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var hotKeySerial: UInt32 = 0
    private let callback: @MainActor @Sendable () -> Void

    private var observer: NSObjectProtocol?

    /// Installs the handler once and registers the current Settings combo. The
    /// `keyCode`/`modifiers` arguments are an explicit override (mainly for
    /// tests); when omitted, the combo comes from `Settings`. The hotkey also
    /// observes `.scratchMateSettingsChanged` so a rebind in Settings re-registers
    /// automatically, without the AppDelegate having to wire it up.
    init(
        keyCode: UInt32? = nil,
        modifiers: UInt32? = nil,
        callback: @escaping @MainActor @Sendable () -> Void
    ) {
        self.callback = callback
        installHandler()
        register(keyCode: keyCode ?? Self.currentKeyCode(),
                 modifiers: modifiers ?? Self.currentModifiers())

        // Re-register when the user rebinds. The combo lives in Settings, so we
        // just reload on any settings change (cheap: unregister + register).
        observer = NotificationCenter.default.addObserver(
            forName: .scratchMateSettingsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            self?.reload()
        }
    }

    /// Re-reads the combination from Settings and re-registers the hotkey. Safe
    /// to call any number of times; it unregisters the previous combo first.
    func reload() {
        register(keyCode: Self.currentKeyCode(), modifiers: Self.currentModifiers())
    }

    // MARK: - Settings to Carbon translation

    /// Default key code (Space) used when the stored value is missing or out of
    /// range, so a corrupted/tampered UserDefaults cannot trap the app at launch.
    private static let defaultKeyCode = UInt32(kVK_Space)

    private static func currentKeyCode() -> UInt32 {
        let raw = Settings.hotKeyCode
        // UInt32(_:) traps on a negative or oversized Int; fall back instead.
        guard raw >= 0, raw <= Int(UInt32.max) else { return defaultKeyCode }
        return UInt32(raw)
    }

    /// Maps an NSEvent.ModifierFlags raw value (what the recorder stores) to the
    /// Carbon modifier mask RegisterEventHotKey expects.
    private static func currentModifiers() -> UInt32 {
        let raw = Settings.hotKeyModifiers
        // UInt(_:) traps on a negative Int; a corrupted value falls back to cmd+shift.
        let flags = raw >= 0
            ? NSEvent.ModifierFlags(rawValue: UInt(raw))
            : NSEvent.ModifierFlags([.command, .shift])
        return carbonModifiers(from: flags)
    }

    /// Translates AppKit modifier flags to the Carbon bit mask. Exposed so the
    /// recorder and the registration agree on the conversion in one place.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        return carbon
    }

    // MARK: - Carbon plumbing

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { hotKey.callback() }
                }
                return noErr
            },
            1, &eventType, selfPtr, &handler
        )
    }

    private func register(keyCode: UInt32, modifiers: UInt32) {
        // Register the new combo into a temporary ref FIRST and only swap once it
        // succeeds, so a failing registration leaves the previous hotkey working
        // instead of unregistering it for nothing. A fresh id each time avoids an
        // eventHotKeyExistsErr collision with the still-active previous registration.
        hotKeySerial &+= 1
        let hkID = EventHotKeyID(signature: OSType(0x534D_4854), id: hotKeySerial)  // 'SMHT'
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode, modifiers, hkID, GetApplicationEventTarget(), 0, &newRef
        )
        guard status == noErr, let newRef else {
            NSLog("ScratchMate: RegisterEventHotKey failed (status \(status)); keeping previous hotkey")
            return
        }
        if let ref { UnregisterEventHotKey(ref) }
        self.ref = newRef
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}
