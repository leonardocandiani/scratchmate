import Foundation

/// Central preferences store backed by UserDefaults (mirrors the Krit pattern).
/// Every setter posts `.scratchMateSettingsChanged` so the UI reacts live.
///
/// Default convention: numeric/bool keys that need a non-zero default read
/// through `d.object(forKey:) == nil` so a never-set key falls back to the
/// design default instead of UserDefaults' implicit 0/false.
nonisolated enum Settings {
    // UserDefaults.standard is thread-safe per Apple; safe to share nonisolated.
    private nonisolated(unsafe) static let d = UserDefaults.standard

    // MARK: - Appearance

    static var themeID: String {
        get { d.string(forKey: "themeID") ?? "scratch-dark" }
        set { d.set(newValue, forKey: "themeID"); notify() }
    }

    /// When on, the active theme follows the system appearance: lightThemeID in
    /// Light mode, darkThemeID in Dark mode, ignoring themeID.
    static var themeFollowsSystem: Bool {
        get { d.bool(forKey: "themeFollowsSystem") }
        set { d.set(newValue, forKey: "themeFollowsSystem"); notify() }
    }

    /// Theme used in system Light mode when themeFollowsSystem is on.
    static var lightThemeID: String {
        get { d.string(forKey: "lightThemeID") ?? "paper" }
        set { d.set(newValue, forKey: "lightThemeID"); notify() }
    }

    /// Theme used in system Dark mode when themeFollowsSystem is on.
    static var darkThemeID: String {
        get { d.string(forKey: "darkThemeID") ?? "scratch-dark" }
        set { d.set(newValue, forKey: "darkThemeID"); notify() }
    }

    /// Tint opacity over the background blur (0 = fully translucent, 0.9 = near
    /// solid). Default sits low so the glass shows through immediately (the
    /// aesthetic is the priority). Range now matches Antinote's 0 to 90%.
    static var opacity: Double {
        get { d.object(forKey: "opacity") == nil ? 0.65 : d.double(forKey: "opacity") }
        set { d.set(newValue, forKey: "opacity"); notify() }
    }

    /// Persists opacity mid-drag WITHOUT the global settings rebuild (which would
    /// tear down the very slider being dragged and stall it). Posts a lightweight
    /// preview notification the editor listens to for live translucency. Commit
    /// the final value through the normal `opacity` setter on mouse-up.
    static func setOpacityLive(_ value: Double) {
        d.set(value, forKey: "opacity")
        NotificationCenter.default.post(name: .scratchMateOpacityPreview, object: nil)
    }

    /// Master toggle for translucency. When off, the editor uses an opaque
    /// surface regardless of the opacity slider (mirrors a "solid window" mode).
    static var translucencyEnabled: Bool {
        get { d.object(forKey: "translucencyEnabled") == nil ? true : d.bool(forKey: "translucencyEnabled") }
        set { d.set(newValue, forKey: "translucencyEnabled"); notify() }
    }

    /// In translucency mode, draw the top/bottom chrome bars as solid fills so
    /// text stays legible over busy desktops (Antinote's "solid bars" option).
    static var solidBarsInTranslucency: Bool {
        get { d.bool(forKey: "solidBarsInTranslucency") }
        set { d.set(newValue, forKey: "solidBarsInTranslucency"); notify() }
    }

    /// Accent source: "system" (controlAccentColor), "caret" (brand amber), or
    /// "custom" (the color stored in `customAccentHex`).
    static var accentSource: String {
        get { d.string(forKey: "accentSource") ?? "caret" }
        set { d.set(newValue, forKey: "accentSource"); notify() }
    }

    /// Custom accent as "#RRGGBB", used only when `accentSource == "custom"`.
    static var customAccentHex: String {
        get { d.string(forKey: "customAccentHex") ?? "#FFB454" }
        set { d.set(newValue, forKey: "customAccentHex"); notify() }
    }

    // MARK: - General

    /// App presence: "menubar" (accessory, no Dock), "dock" (Dock icon, no menu
    /// bar item), "both", or "none" (hotkey only). Default keeps the menu bar agent.
    static var appPresence: String {
        get { d.string(forKey: "appPresence") ?? "menubar" }
        set { d.set(newValue, forKey: "appPresence"); notify() }
    }

    static var launchAtLogin: Bool {
        get { d.bool(forKey: "launchAtLogin") }
        set { d.set(newValue, forKey: "launchAtLogin"); notify() }
    }

    /// Create a fresh note every time the app launches.
    static var createNoteOnLaunch: Bool {
        get { d.bool(forKey: "createNoteOnLaunch") }
        set { d.set(newValue, forKey: "createNoteOnLaunch"); notify() }
    }

    /// When to start a new note after the window closes, in seconds. 0 = always
    /// a new note, -1 = never. Discrete steps: 0, 180, 1800, 3600, 86400, -1.
    static var newNoteAfterCloseSeconds: Int {
        get { d.object(forKey: "newNoteAfterCloseSeconds") == nil ? -1 : d.integer(forKey: "newNoteAfterCloseSeconds") }
        set { d.set(newValue, forKey: "newNoteAfterCloseSeconds"); notify() }
    }

    /// Hide the window automatically when it loses focus.
    static var hideWhenUnfocused: Bool {
        get { d.object(forKey: "hideWhenUnfocused") == nil ? true : d.bool(forKey: "hideWhenUnfocused") }
        set { d.set(newValue, forKey: "hideWhenUnfocused"); notify() }
    }

    /// Show the "What's new" window after the app updates to a new version.
    static var showWhatsNewAfterUpdate: Bool {
        get { d.object(forKey: "showWhatsNewAfterUpdate") == nil ? true : d.bool(forKey: "showWhatsNewAfterUpdate") }
        set { d.set(newValue, forKey: "showWhatsNewAfterUpdate"); notify() }
    }

    // MARK: - Editor

    /// Editor font family. Empty string means the design default (SF Mono).
    static var editorFontFamily: String {
        get { d.string(forKey: "editorFontFamily") ?? "" }
        set { d.set(newValue, forKey: "editorFontFamily"); notify() }
    }

    /// Editor font size in points. Default is the medium step (13).
    static var editorFontSize: Double {
        get { d.object(forKey: "editorFontSize") == nil ? 13 : d.double(forKey: "editorFontSize") }
        set { d.set(newValue, forKey: "editorFontSize"); notify() }
    }

    /// Language id assigned to brand-new notes (matches EditorViewController's list).
    /// Defaults to "auto" so a new note's format is guessed from its content.
    static var defaultNoteLanguage: String {
        get { d.string(forKey: "defaultNoteLanguage") ?? "auto" }
        set { d.set(newValue, forKey: "defaultNoteLanguage"); notify() }
    }

    /// Doubles the editor text size on top of editorFontSize (large-text mode).
    static var doubleTextSize: Bool {
        get { d.bool(forKey: "doubleTextSize") }
        set { d.set(newValue, forKey: "doubleTextSize"); notify() }
    }

    // MARK: - Behavior

    /// Show the chrome (footer) at all times instead of only on hover.
    static var alwaysShowChrome: Bool {
        get { d.bool(forKey: "alwaysShowChrome") }
        set { d.set(newValue, forKey: "alwaysShowChrome"); notify() }
    }

    /// New notes start pinned (panel stays open when focus is lost).
    static var defaultPinned: Bool {
        get { d.bool(forKey: "defaultPinned") }
        set { d.set(newValue, forKey: "defaultPinned"); notify() }
    }

    /// Copy the current selection to the clipboard as you select it (Antinote
    /// parity; handy for grabbing snippets). Off by default so it never surprises
    /// the system clipboard.
    static var autoCopyOnSelect: Bool {
        get { d.bool(forKey: "autoCopyOnSelect") }
        set { d.set(newValue, forKey: "autoCopyOnSelect"); notify() }
    }

    /// Show the "n/total" note counter in the footer.
    static var showNoteCount: Bool {
        get { d.object(forKey: "showNoteCount") == nil ? true : d.bool(forKey: "showNoteCount") }
        set { d.set(newValue, forKey: "showNoteCount"); notify() }
    }

    // MARK: - Shortcuts

    /// Global hotkey virtual key code (Carbon kVK_*). Default kVK_Space (49).
    static var hotKeyCode: Int {
        get { d.object(forKey: "hotKeyCode") == nil ? 49 : d.integer(forKey: "hotKeyCode") }
        set { d.set(newValue, forKey: "hotKeyCode"); notify() }
    }

    /// Global hotkey modifier flags stored as the raw value of
    /// NSEvent.ModifierFlags. Default = command + shift.
    static var hotKeyModifiers: Int {
        get {
            d.object(forKey: "hotKeyModifiers") == nil
                ? Int(defaultHotKeyModifierRaw)
                : d.integer(forKey: "hotKeyModifiers")
        }
        set { d.set(newValue, forKey: "hotKeyModifiers"); notify() }
    }

    /// The default hotkey modifier raw value (command + shift), exposed so HotKey
    /// and the recorder agree on the fallback without duplicating the constant.
    static var defaultHotKeyModifierRaw: UInt {
        // NSEvent.ModifierFlags.command (1 << 20) | .shift (1 << 17).
        (1 << 20) | (1 << 17)
    }

    // MARK: - Notes & Privacy

    /// Days until an empty/old note becomes a cleanup candidate. 0 = never.
    /// Discrete steps in the UI: 0, 1, 7, 30, 365.
    static var autoExpireDays: Int {
        get { d.integer(forKey: "autoExpireDays") }
        set { d.set(newValue, forKey: "autoExpireDays"); notify() }
    }

    // MARK: - Advanced

    /// Check for updates automatically on launch.
    static var autoCheckUpdates: Bool {
        get { d.object(forKey: "autoCheckUpdates") == nil ? true : d.bool(forKey: "autoCheckUpdates") }
        set { d.set(newValue, forKey: "autoCheckUpdates"); notify() }
    }

    /// Download updates automatically once found (still asks before installing).
    static var autoDownloadUpdates: Bool {
        get { d.bool(forKey: "autoDownloadUpdates") }
        set { d.set(newValue, forKey: "autoDownloadUpdates"); notify() }
    }

    // MARK: - Reset

    /// Restores every key managed here to its default by removing it, then posts
    /// a single change notification so the whole UI rebuilds at once.
    static func resetAll() {
        let keys = [
            "themeID", "themeFollowsSystem", "lightThemeID", "darkThemeID",
            "opacity", "translucencyEnabled", "solidBarsInTranslucency",
            "accentSource", "customAccentHex",
            "appPresence", "launchAtLogin", "createNoteOnLaunch", "newNoteAfterCloseSeconds",
            "hideWhenUnfocused", "showWhatsNewAfterUpdate",
            "editorFontFamily", "editorFontSize", "defaultNoteLanguage", "doubleTextSize",
            "alwaysShowChrome", "defaultPinned", "autoCopyOnSelect", "showNoteCount",
            "hotKeyCode", "hotKeyModifiers",
            "autoExpireDays", "autoCheckUpdates", "autoDownloadUpdates",
        ]
        keys.forEach { d.removeObject(forKey: $0) }
        notify()
    }

    private static func notify() {
        NotificationCenter.default.post(name: .scratchMateSettingsChanged, object: nil)
    }
}

extension Notification.Name {
    nonisolated static let scratchMateSettingsChanged = Notification.Name("scratchMateSettingsChanged")
    /// Live opacity preview during a slider drag: the editor reapplies translucency
    /// without the settings form rebuilding (see Settings.setOpacityLive).
    nonisolated static let scratchMateOpacityPreview = Notification.Name("scratchMateOpacityPreview")
}
